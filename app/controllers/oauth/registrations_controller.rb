# frozen_string_literal: true

module Oauth
  class RegistrationsController < ApplicationController
    skip_forgery_protection

    wrap_parameters false

    # POST /oauth/registrations — RFC 7591-style dynamic client registration for MCP clients.
    def create
      redirect_uri = normalize_redirect_uris(registration_params[:redirect_uris])
      if redirect_uri.blank?
        return render json: {
          error: 'invalid_client_metadata',
          error_description: 'redirect_uris is required'
        }, status: :bad_request
      end

      application = Doorkeeper::Application.new(
        name: registration_params[:client_name].presence || 'MCP client',
        redirect_uri: redirect_uri,
        confidential: false,
        scopes: 'mcp:access'
      )

      if application.save
        render json: {
          client_name: application.name,
          client_id: application.uid,
          client_id_issued_at: application.created_at.to_i,
          redirect_uris: application.redirect_uri.split
        }, status: :created
      else
        render json: {
          error: 'invalid_client_metadata',
          error_description: application.errors.full_messages.join(', ')
        }, status: :bad_request
      end
    end

    private

    def registration_params
      if params[:oauth_application].present?
        params.require(:oauth_application).permit(:client_name, redirect_uris: [])
      else
        params.permit(:client_name, redirect_uris: [])
      end
    end

    def normalize_redirect_uris(uris)
      list = Array(uris).flatten.compact.map(&:strip).reject(&:blank?)
      return '' if list.empty?

      list.join("\n")
    end
  end
end
