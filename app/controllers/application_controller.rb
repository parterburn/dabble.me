class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  before_filter :js_action
  before_filter :tag_request
  before_filter :configure_permitted_parameters, if: :devise_controller?

  def redirect_back_or_to(default)
    redirect_to session.delete(:return_to) || default
  end

  def store_location
    session[:return_to] = request.referrer
  end

  def authenticate_admin!
    unless current_user.is_admin?
      flash[:alert] = "Not authorized"
      redirect_to entries_path
    end
  end

  protected

  def configure_permitted_parameters
    added_attrs = [:first_name, :last_name, :email, :password, :password_confirmation]
    devise_parameter_sanitizer.permit :sign_up, keys: added_attrs
    devise_parameter_sanitizer.permit :account_update, keys: added_attrs + [{ frequency: [] }, :way_back_past_entries, :send_past_entry, :send_time, :send_timezone, :past_filter, :current_password]
  end  

  def js_action
    @js_action = [controller_path.camelize.gsub('::', '_'), action_name].join('_')
  end

  def tag_request
    if current_user
      Sqreen.identify({ id: current_user.id, email: current_user.email })
    end    
  end
end

if RUBY_VERSION>='2.6.0'
  if Rails.version < '5'
    class ActionController::TestResponse < ActionDispatch::TestResponse
      def recycle!
        # hack to avoid MonitorMixin double-initialize error:
        @mon_mutex_owner_object_id = nil
        @mon_mutex = nil
        initialize
      end
    end
  else
    puts "Monkeypatch for ActionController::TestResponse no longer needed"
  end
end
