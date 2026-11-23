# frozen_string_literal: true

namespace :admin do
  # Leaves an admin with a passkey or an emailed code (plus 2FA, if on) as their only sign-in.
  #   bin/rails "admin:remove_password[admin@example.com]"
  # Their other browsers are signed out; the app stays signed in. Undo by setting a password
  # again (Account Security asks for an emailed code, or use Forgot password).
  desc 'Remove an admin account\'s password (passkey or emailed code sign-in only)'
  task :remove_password, [:email] => :environment do |_task, args|
    email = args[:email].to_s.strip.downcase
    abort 'Usage: bin/rails "admin:remove_password[admin@example.com]"' if email.blank?

    user = User.find_for_authentication(email: email)
    abort "No account for #{email}." unless user

    AdminAccounts.remove_password!(user)
    puts "Removed the password for #{user.email}. Sign in with a passkey (#{user.webauthn_credentials.count} on file) or an emailed code#{' plus 2FA' if user.otp_enabled?}."
  rescue AdminAccounts::Refused => e
    abort e.message
  end
end
