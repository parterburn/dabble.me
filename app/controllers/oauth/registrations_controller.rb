# frozen_string_literal: true

module Oauth
  class RegistrationsController < ApplicationController
    skip_forgery_protection

    wrap_parameters false

    # POST /oauth/registrations — RFC 7591-style dynamic client registration for MCP clients.
    def create
      uris = extract_redirect_uris(registration_params[:redirect_uris])
      if uris.empty?
        return render json: {
          error: 'invalid_client_metadata',
          error_description: 'redirect_uris is required'
        }, status: :bad_request
      end

      unless uris.all? { |uri| allowed_redirect_uri?(uri) }
        return render json: {
          error: 'invalid_redirect_uri',
          error_description: 'redirect_uris must use https (or http for loopback hosts)'
        }, status: :bad_request
      end

      redirect_uri = uris.join("\n")

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

    def extract_redirect_uris(uris)
      Array(uris).flatten.compact.map(&:strip).reject(&:blank?)
    end

    def allowed_redirect_uri?(raw_uri)
      uri = URI.parse(raw_uri.to_s)
      scheme = uri.scheme.to_s.downcase
      host = uri.host.to_s.downcase
      return false if host.blank? || uri.fragment.present?

      if scheme == 'https'
        true
      elsif scheme == 'http'
        %w[localhost 127.0.0.1 ::1 [::1]].include?(host)
      else
        false
      end
    rescue URI::InvalidURIError
      false
    end
  end
end
