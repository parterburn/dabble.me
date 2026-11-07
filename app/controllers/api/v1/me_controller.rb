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
          can_write: user.is_pro?,
          can_search: user.is_pro?,
          settings_url: "#{ApplicationHelper.site_public_base_url}/settings",
          security_url: "#{ApplicationHelper.site_public_base_url}/security"
        }
      end
    end
  end
end
