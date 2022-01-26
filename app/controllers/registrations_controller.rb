# Devise Override Controller
class RegistrationsController < Devise::RegistrationsController
  before_action :require_user, only: [:security, :update, :edit]
  after_action :track_ga_event, only: :create
  prepend_before_action :check_captcha, only: [:create]

  def edit
    cookies.permanent[:viewed_settings] = true
    super
  end

  def create
    super do
      resource.referrer = request.env['affiliate.tag']
      resource.save
    end
  end

  def update
    if params[:submit_method] == "delete account"
      if current_user.valid_password?(params[:user][:current_password])
        current_user.destroy
        redirect_to root_path, notice: "Your account has been deleted."
      else
        flash[:alert] = "Incorrect current password."
        redirect_back(fallback_location: security_path)
      end
    else # updating
      if params[:frequency].present?
        user.frequency = []
        params[:frequency].each do |freq|
          user.frequency << freq[0]
        end
      end

      params[:user].parse_time_select! :send_time
      successfully_updated =  if needs_password?
                                user.update_with_password(devise_parameter_sanitizer.sanitize(:account_update))
                              else
                                # remove the virtual current_password attribute
                                # update_without_password doesn't know how to ignore it
                                params[:user].delete(:current_password)
                                user.update_without_password(devise_parameter_sanitizer.sanitize(:preferences))
                              end

      if successfully_updated
        set_flash_message :notice, :updated
        # Sign in the user bypassing validation in case their password changed
        bypass_sign_in user
      else
        flash[:alert] = flash[:alert].to_a.concat resource.errors.full_messages
      end
      redirect_back(fallback_location: edit_user_registration_path)
    end
  end

  def settings
    if !user_signed_in? && user.present? # allow unsubscribing without logging in
      cookies.permanent[:viewed_settings] = true
      render 'devise/registrations/settings'
    else
      redirect_to edit_user_registration_path
    end
  end

  def destroy
    if current_user.valid_password?(params[:user][:current_password])
      super
    else
      flash[:alert] = "Incorrect current password."
      redirect_back(fallback_location: security_path)
    end
  end

  def security
    render 'devise/registrations/security'
  end

  def unsubscribe
    if params[:frequency].present? && params[:unsub_all].blank?
      user.frequency = []
      params[:frequency].each do |freq|
        user.frequency << freq[0]
      end
    elsif params[:unsub_all].present?
      user.frequency = []
    end

    params[:user].parse_time_select! :send_time
    if user.update_without_password(devise_parameter_sanitizer.sanitize(:preferences))
      if user.frequency.present?
        set_flash_message :notice, :updated
      else
        flash[:notice] = 'You are now unsubscribed from all emails.'
      end
    else
      set_flash_message :error, 'Could not update.'
    end

    redirect_to settings_path(user.user_key)
  end

  private

  def check_captcha
    Sqreen.signup_track(email: sign_up_params[:email])
    if ENV['RECAPTCHA_SITE_KEY'].blank? || (verify_recaptcha || ENV['CI'] == "true")
      true
    else
      self.resource = resource_class.new sign_up_params
      flash[:alert] = 'Bad recaptcha.'
      respond_with_navigational(resource) { render :new }
    end
  end

  def track_ga_event
    return nil unless user.id.present?
    if ENV['GOOGLE_ANALYTICS_ID'].present?
      tracker = Staccato.tracker(ENV['GOOGLE_ANALYTICS_ID'])
      tracker.event(category: 'User', action: 'Create', label: user.user_key)
    end
  end

  # check if we need password to update user data
  # ie if password or email was changed
  def needs_password?
    params[:submit_method] == "security" ||
      (user_params[:email].present? && user.email != user_params[:email]) ||
      (user_params[:password].present? || user_params[:password_confirmation].present?)
  end

  def user_params
    params.require(:user).permit(:hashtag, :first_name, :last_name, :send_time, :send_timezone, :way_back_past_entries, :send_past_entry, :past_filter, :email, :password, :password_confirmation, hashtags_attributes: [:tag, :date])
  end

  def user
    @user ||= user_signed_in? ? current_user : User.find_by(user_key: params[:user_key])
  end
  helper_method :user

  def require_user
    return nil if user_signed_in?

    store_location_for(:user, request.fullpath)
    redirect_to new_user_session_path, alert: 'You must be logged in to access this page.'
  end
end
