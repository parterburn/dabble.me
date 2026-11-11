# frozen_string_literal: true

module Api
  module V1
    class MeController < BaseController
      def show
        user = current_user
        render json: {
          id: user.id,
          email: user.email,
          first_name: user.first_name,
          name: user.full_name&.strip.presence,
          plan: user.is_pro? ? 'pro' : 'free',
          is_pro: user.is_pro?,
          timezone: user.send_timezone,
          today: Mcp::Tools::Helpers.default_entry_date_iso8601(user),
          entry_count: user.entries.count,
          can_write: true,
          can_add_photos: user.is_pro?,
          can_edit: user.is_pro?,
          can_delete: true,
          can_add_links: user.is_pro?,
          can_search: user.is_pro?,
          can_see_stats: user.is_pro?,
          settings_url: "#{ApplicationHelper.site_public_base_url}/settings",
          security_url: "#{ApplicationHelper.site_public_base_url}/security",
          # Connecting Claude/ChatGPT (MCP) needs PRO.
          ai_connectors: {
            claude_url: ApplicationHelper.claude_plugin_directory_url,
            chatgpt_url: ApplicationHelper.chatgpt_plugin_directory_url,
            guide_url: "#{ApplicationHelper.site_public_base_url}/mcp-server",
            requires_pro: !user.is_pro?,
            # Dabble Me for iOS 1.0 decodes this as a required Bool.
            requires_security_setup: false
          }
        }
      end
    end
  end
end
