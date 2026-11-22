# frozen_string_literal: true

module Api
  module V1
    class MeController < BaseController
      # A cap on each name sent here (the web form has none).
      MAX_NAME_LENGTH = 100

      def show
        render json: me_json(current_user)
      end

      # PATCH /api/v1/me { first_name: "Ann", last_name: "Lee" } (either one). A blank value clears
      # it; a missing one is left as it is. Returns the account as GET does.
      def update
        user = current_user
        %i[first_name last_name].each do |key|
          # JSON null means "not sent" (see .cursor/BUGBOT.md); only a string is a name.
          next unless params.key?(key) && !params[key].nil?
          return render_error(:unprocessable_content, 'invalid', 'A name must be text.') unless params[key].is_a?(String)

          value = params[key].strip
          if value.length > MAX_NAME_LENGTH
            return render_error(:unprocessable_content, 'invalid', "That name is too long (#{MAX_NAME_LENGTH} characters at most).")
          end

          user.public_send("#{key}=", value.presence)
        end

        if user.save
          render json: me_json(user)
        else
          render_error(:unprocessable_content, 'invalid', 'Could not save your name.', details: user.errors.full_messages)
        end
      end

      private

      def me_json(user)
        {
          id: user.id,
          email: user.email,
          first_name: user.first_name,
          last_name: user.last_name,
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
          # The app offers to add a passkey until there is one (Api::V1::PasskeysController).
          has_passkey: user.webauthn_credentials.exists?,
          # An account made by email code may have no password: the app confirms Delete Account
          # and adding a passkey with an emailed code instead (Api::V1::ConfirmationCodesController).
          has_password: user.has_password?,
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
