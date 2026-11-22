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
          # The same zone by its IANA name ("America/Denver"), which the app's clock understands.
          timezone_identifier: ActiveSupport::TimeZone[user.send_timezone.to_s]&.tzinfo&.name,
          today: Mcp::Tools::Helpers.default_entry_date_iso8601(user),
          entry_count: user.entries.count,
          can_write: true,
          can_add_photos: user.is_pro?,
          can_edit: user.is_pro?,
          can_delete: true,
          can_add_links: user.is_pro?,
          can_search: user.is_pro?,
          can_see_stats: user.is_pro?,
          # In-app purchase (from build 116): the appAccountToken to buy with, where PRO comes
          # from ("apple", "web" or nil), and the App Store subscription that gives it.
          apple_account_token: user.apple_account_token!,
          # No new subscriptions once a closing is announced, as on the web (refuse_when_closing).
          # Purchases already made are still reported and restored.
          can_buy_in_app: !SiteClosure.announced?,
          **AppleSubscriptionsController.status_json(user).slice(:pro_source, :apple_subscription),
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
