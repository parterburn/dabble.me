# mailgun_rails does not expose RestClient timeout options. Keep Mailgun API
# stalls from consuming the full Rack::Timeout window in synchronous callers.
module MailgunRails
  class Client
    OPEN_TIMEOUT = Integer(ENV.fetch('MAILGUN_OPEN_TIMEOUT', 5))
    READ_TIMEOUT = Integer(ENV.fetch('MAILGUN_READ_TIMEOUT', 30))

    def send_message(options)
      RestClient::Request.execute(
        method: :post,
        url: mailgun_url,
        payload: options,
        verify_ssl: verify_ssl,
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      )
    end
  end
end
