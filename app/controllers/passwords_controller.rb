class PasswordsController < Devise::PasswordsController
  layout 'marketing'

  def create
    super
  end
end
