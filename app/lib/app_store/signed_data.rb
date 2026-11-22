# frozen_string_literal: true

module AppStore
  # Verifies a JWS that Apple signed (a transaction, renewal info, a notification, or an API
  # response's parts) and returns its payload. The way Apple's own App Store Server Library does:
  #
  # - the header's x5c chain is leaf, intermediate, then Apple Root CA - G3, and that root is
  #   the copy kept in config/certs (compared byte for byte, never taken from the request);
  # - the chain verifies (signatures, validity dates, CA constraints) under OpenSSL;
  # - the leaf carries Apple's App Store receipt-signing marker (1.2.840.113635.100.6.11.1) and
  #   the intermediate the WWDR marker (1.2.840.113635.100.6.2.1);
  # - the JWS is ES256 and its signature verifies with the leaf's key.
  #
  # The payload's bundle and environment are checked by the callers, which know what they expect.
  module SignedData
    LEAF_OID = "1.2.840.113635.100.6.11.1"
    INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1"
    ROOT_PATH = Rails.root.join("config/certs/AppleRootCA-G3.pem")

    module_function

    def verify!(jws)
      raise VerificationError, "missing signed data" unless jws.is_a?(String) && jws.count(".") == 2

      header = decode_header(jws)
      raise VerificationError, "unexpected algorithm" unless header["alg"] == "ES256"

      leaf = verified_leaf(header["x5c"])
      payload, = JWT.decode(jws, leaf.public_key, true, algorithms: ["ES256"])
      raise VerificationError, "payload is not an object" unless payload.is_a?(Hash)

      payload
    rescue JWT::DecodeError, OpenSSL::X509::CertificateError, OpenSSL::PKey::PKeyError, ArgumentError, JSON::ParserError => e
      raise VerificationError, "signature did not verify (#{e.class})"
    end

    # Specs swap in their own root.
    def root_certificates
      @root_certificates ||= [OpenSSL::X509::Certificate.new(File.read(ROOT_PATH))]
    end

    def root_certificates=(certs)
      @root_certificates = certs
    end

    def decode_header(jws)
      encoded = jws.split(".", 2).first
      header = JSON.parse(Base64.urlsafe_decode64(encoded + "=" * (-encoded.length % 4)))
      raise VerificationError, "header is not an object" unless header.is_a?(Hash)

      header
    end

    def verified_leaf(x5c)
      unless x5c.is_a?(Array) && x5c.length == 3 && x5c.all?(String)
        raise VerificationError, "certificate chain must be leaf, intermediate, root"
      end

      leaf, intermediate, root = x5c.map { |der| OpenSSL::X509::Certificate.new(Base64.strict_decode64(der)) }
      trusted = root_certificates.find { |known| known.to_der == root.to_der }
      raise VerificationError, "root is not Apple's" unless trusted
      raise VerificationError, "leaf is not an App Store signing certificate" unless oid?(leaf, LEAF_OID)
      raise VerificationError, "intermediate is not Apple WWDR" unless oid?(intermediate, INTERMEDIATE_OID)

      store = OpenSSL::X509::Store.new
      store.add_cert(trusted)
      unless store.verify(leaf, [intermediate])
        raise VerificationError, "certificate chain did not verify (#{store.error_string})"
      end

      leaf
    end

    def oid?(cert, oid)
      cert.extensions.any? { |ext| ext.oid == oid }
    end

    # Apple's timestamps are milliseconds since the epoch.
    def time(ms)
      ms.present? ? Time.at(ms.to_i / 1000, ms.to_i % 1000, :millisecond).utc : nil
    end
  end
end
