require 'addressable/uri'

class ValidUrlValidator < ActiveModel::EachValidator

  def validate_each(record,attribute,value)
    if value.present?
      begin
        uri = Addressable::URI.parse(value)

        if !["http","https","ftp"].include?(uri.scheme)
          raise Addressable::URI::InvalidURIError
        end
      rescue Addressable::URI::InvalidURIError
        record.errors[attribute] << "does not seem to be valid"
      end
    end
  end

end
