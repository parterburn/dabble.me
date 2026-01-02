class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  before_action :js_action
  before_action :set_user_today
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :identify_current_user_to_sentry

  rescue_from Rack::Timeout::RequestTimeoutException, with: :handle_timeout

  def redirect_back_or_to(default)
    redirect_to session&.delete(:return_to) || default
  end

  def store_location
    session[:return_to] = request.referrer
  end

  def authenticate_admin!
    unless current_user.admin?
      flash[:alert] = "Not authorized"
      redirect_to entries_path
    end
  end

  def identify_current_user_to_sentry
    if current_user
      Sentry.set_user(id: current_user.id, email: current_user.email)
      Sentry.set_tags(plan: current_user.plan)
    end
    extras = { params: params.to_unsafe_h, url: request.url }
    Sentry.set_extras(extras)
  end

  protected

  def configure_permitted_parameters
    added_attrs = [:first_name, :last_name, :email, :password, :password_confirmation]
    devise_parameter_sanitizer.permit :sign_up, keys: added_attrs
    devise_parameter_sanitizer.permit :account_update, keys: [:email, :password, :password_confirmation]
    devise_parameter_sanitizer.permit :preferences, keys: added_attrs + [{ frequency: [] }, :way_back_past_entries, :send_past_entry, :send_time, :send_timezone, :past_filter, :current_password, hashtags_attributes: [:tag, :date]]
  end

  def js_action
    @js_action = [controller_path.camelize.gsub('::', '_'), action_name].join('_')
  end

  def handle_timeout(exception)
    Sentry.capture_message("Timeout error", level: :error, extra: { params: params, url: request.url })
    render "errors/timeout"
  end

  def set_user_today
    @user_today = Time.now.in_time_zone(current_user&.send_timezone.presence || "UTC").to_date
  end
end
