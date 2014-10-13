class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  before_filter :js_action

  before_filter :configure_permitted_parameters, if: :devise_controller?

  def admin
    if current_user && current_user.is_admin?
      @users = User.all
      @entries = Entry.all
      render "admin/index"
    else
      flash[:alert] = "Not authorized"
      redirect_to root_path      
    end
  end

  def redirect_back_or_to(default, id=0)
    redirect_to session.delete(:return_to) || default
  end

  def store_location
    session[:return_to] = request.referrer
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.for(:sign_up) do |u|
      u.permit(:first_name, :last_name, :email, :password, :password_confirmation)
    end
    devise_parameter_sanitizer.for(:account_update) do |u|
      u.permit(:first_name, :last_name, :email, :password, :password_confirmation,  {:frequency => []}, :send_past_entry, :send_time, :send_timezone, :current_password)
    end
  end

  def js_action
    @js_action = [controller_path.camelize.gsub("::","_"),action_name].join('_')
  end  
  
end
