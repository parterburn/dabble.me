class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  before_filter :js_action

  before_filter :configure_permitted_parameters, if: :devise_controller?
  before_filter :set_format

  def redirect_back_or_to(default)
    redirect_to session.delete(:return_to) || default
  end

  def store_location
    session[:return_to] = request.referrer
  end

  def authenticate_admin!
    unless current_user.is_admin?
      flash[:alert] = "Not authorized"
      redirect_to past_entries_path
    end
  end

  protected

  def set_format
    request.format = 'html' if request.format != 'html'
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.for(:sign_up) do |u|
      u.permit(:first_name, :last_name, :email, :password, :password_confirmation)
    end
    devise_parameter_sanitizer.for(:account_update) do |u|
      u.permit(:first_name, :last_name, :email, :password, :password_confirmation,  { frequency: [] }, :send_past_entry, :send_time, :send_timezone, :current_password)
    end
  end

  def js_action
    @js_action = [controller_path.camelize.gsub('::', '_'), action_name].join('_')
  end
end
