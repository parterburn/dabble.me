# frozen_string_literal: true

module Oauth
  class AuthorizedApplicationsController < Doorkeeper::AuthorizedApplicationsController
    def index
      respond_to do |format|
        format.html { redirect_to settings_mcp_path }
        format.json do
          @applications = Doorkeeper.config.application_model.authorized_for(current_resource_owner)
          render json: @applications, current_resource_owner: current_resource_owner
        end
      end
    end

    def destroy
      Doorkeeper.config.application_model.revoke_tokens_and_grants_for(
        params[:id],
        current_resource_owner
      )

      respond_to do |format|
        format.html do
          redirect_to settings_mcp_path, notice: I18n.t(
            :notice,
            scope: %i[doorkeeper flash authorized_applications destroy]
          )
        end
        format.json { head :no_content }
      end
    end
  end
end
