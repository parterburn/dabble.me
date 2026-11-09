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
          # Connecting Claude/ChatGPT (MCP) needs PRO plus a passkey or 2FA on the account.
          ai_connectors: {
            claude_url: ApplicationHelper.claude_plugin_directory_url,
            chatgpt_url: ApplicationHelper.chatgpt_plugin_directory_url,
            guide_url: "#{ApplicationHelper.site_public_base_url}/mcp-server",
            requires_pro: !user.is_pro?,
            requires_security_setup: !user.mcp_security_requirements_met?
          }
        }
      end
    end
  end
end
