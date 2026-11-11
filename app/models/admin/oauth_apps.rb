# frozen_string_literal: true

module Admin
  # OAuth clients for /admin/oauth and the admin user page.
  #
  # Most rows are MCP clients that registered themselves through
  # Oauth::RegistrationsController (Claude, ChatGPT and others register again
  # on reconnects and new devices), plus the iOS app (MobileApp). A user is
  # "connected" to a client while they hold an unrevoked access token for it;
  # refresh tokens keep that working after the access token itself expires.
  class OauthApps
    Registration = Struct.new(:application, :users_connected, :last_token_at, :last_call_at, keyword_init: true) do
      def redirect_hosts
        Admin::OauthApps.redirect_hosts(application)
      end

      def mobile_app?
        MobileApp.client?(application)
      end
    end

    Group = Struct.new(:name, :registrations, :users_connected, keyword_init: true) do
      def last_token_at = registrations.filter_map(&:last_token_at).max
      def last_call_at = registrations.filter_map(&:last_call_at).max
      def first_registered_at = registrations.map { |r| r.application.created_at }.min
      def redirect_hosts = registrations.flat_map(&:redirect_hosts).uniq.sort
      def last_activity_at = [last_token_at, last_call_at, first_registered_at].compact.max
    end

    # One user's history with one client, for the admin user page.
    Connection = Struct.new(:application, :active, :first_token_at, :last_token_at, :last_call_at, keyword_init: true) do
      def redirect_hosts
        Admin::OauthApps.redirect_hosts(application)
      end
    end

    def self.redirect_hosts(application)
      application.redirect_uri.to_s.split.filter_map do |uri|
        parsed = URI.parse(uri)
        parsed.host.presence || "#{parsed.scheme}:"
      rescue URI::InvalidURIError
        nil
      end.uniq
    end

    # The user's clients, newest token first, revoked ones included.
    def self.connections_for(user)
      tokens = Doorkeeper::AccessToken.where(resource_owner_id: user.id)
      first_at = tokens.group(:application_id).minimum(:created_at)
      last_at = tokens.group(:application_id).maximum(:created_at)
      active_ids = tokens.where(revoked_at: nil).distinct.pluck(:application_id).to_set
      calls = McpToolInvocation.where(user_id: user.id, oauth_application_id: first_at.keys)
                               .group(:oauth_application_id).maximum(:created_at)

      Doorkeeper::Application.where(id: first_at.keys).map do |application|
        Connection.new(
          application: application,
          active: active_ids.include?(application.id),
          first_token_at: first_at[application.id],
          last_token_at: last_at[application.id],
          last_call_at: calls[application.id]
        )
      end.sort_by { |c| c.last_token_at || Time.at(0) }.reverse
    end

    attr_reader :name, :email

    # name: part of the client name. email: part of a user's email; keeps only
    # clients one of the matching users has ever authorized.
    def initialize(name: nil, email: nil)
      @name = name.to_s.strip.presence
      @email = email.to_s.strip.presence
    end

    def filtered?
      name.present? || email.present?
    end

    def matching_users
      return User.none unless email

      @matching_users ||= User.where("email ILIKE ?", "%#{User.sanitize_sql_like(email.downcase)}%")
    end

    def applications
      scope = Doorkeeper::Application.all
      scope = scope.where("name ILIKE ?", "%#{Doorkeeper::Application.sanitize_sql_like(name)}%") if name
      if email
        scope = scope.where(id: Doorkeeper::AccessToken.where(resource_owner_id: matching_users.select(:id)).select(:application_id))
      end
      scope
    end

    # Every registration, newest first.
    def registrations
      @registrations ||= begin
        apps = applications.order(created_at: :desc).to_a
        ids = apps.map(&:id)
        active = Doorkeeper::AccessToken.where(application_id: ids, revoked_at: nil)
        users = active.distinct.pluck(:application_id, :resource_owner_id).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
        last_token = Doorkeeper::AccessToken.where(application_id: ids).group(:application_id).maximum(:created_at)
        last_call = McpToolInvocation.where(oauth_application_id: ids).group(:oauth_application_id).maximum(:created_at)

        apps.map do |application|
          Registration.new(
            application: application,
            users_connected: users.fetch(application.id, []),
            last_token_at: last_token[application.id],
            last_call_at: last_call[application.id]
          )
        end
      end
    end

    # Registrations grouped by client name, most recently active first.
    def groups
      registrations.group_by { |r| r.application.name }.map do |group_name, rows|
        Group.new(name: group_name, registrations: rows, users_connected: rows.flat_map(&:users_connected).uniq.size)
      end.sort_by { |g| g.last_activity_at || Time.at(0) }.reverse
    end

    # Emails for the users connected to the listed registrations, by id.
    def user_emails
      ids = registrations.flat_map(&:users_connected).uniq
      @user_emails ||= User.where(id: ids).pluck(:id, :email).to_h
    end
  end
end
