# Devise's failure app, except that a password tried from the code page ("Use password
# instead", which posts from_code) goes back to the code page instead of the email-only Log in
# page, with the same "Invalid email or password" for every address.
class CodeAwareFailureApp < Devise::FailureApp
  def respond
    if from_code_page?
      redirect
    else
      super
    end
  end

  def redirect_url
    if from_code_page?
      Rails.application.routes.url_helpers.email_code_path(password: 1)
    else
      super
    end
  end

  private

  def from_code_page?
    params[:from_code].present? && session[EmailCodesController::EMAIL_CODE_SESSION].present? &&
      warden_options[:recall].present?
  end
end
