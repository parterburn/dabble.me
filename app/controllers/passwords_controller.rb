class PasswordsController < Devise::PasswordsController
  def create
    Sqreen.track('app.reset_password_request')
    super
  end
end
