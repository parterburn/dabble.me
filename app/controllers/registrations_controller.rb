# Devise Override Controller
class RegistrationsController < Devise::RegistrationsController
  after_action :track_ga_event, only: :create

  def edit
    cookies.permanent[:viewed_settings] = true
    super
  end

  def update
    @user = current_user

    @user.frequency = []
    if params[:frequency].present?
      params[:frequency].each do |freq|
        @user.frequency << freq[0]
      end
    end

    params[:user].parse_time_select! :send_time
    successfully_updated =  if needs_password?(@user, user_params)
                              @user.update_with_password(devise_parameter_sanitizer.sanitize(:account_update))
                            else
                              # remove the virtual current_password attribute
                              # update_without_password doesn't know how to ignore it
                              params[:user].delete(:current_password)
                              @user.update_without_password(devise_parameter_sanitizer.sanitize(:account_update))
                            end

    if successfully_updated
      set_flash_message :notice, :updated
      # Sign in the user bypassing validation in case their password changed
      sign_in @user, bypass: true
      redirect_to edit_user_registration_path
    else
      flash[:alert] = flash[:alert].to_a.concat resource.errors.full_messages
      redirect_to edit_user_registration_path
    end
  end

  def settings
    if user_signed_in?
      redirect_to edit_user_registration_path
    else
      @user = User.find_by(user_key: params[:user_key])
      if @user.present?
        cookies.permanent[:viewed_settings] = true
        render 'devise/registrations/settings'
      else
        redirect_to root_path
      end
    end
  end

  def unsubscribe
    @user = User.find_by(user_key: params[:user_key])

    @user.frequency = []
    if params[:frequency].present? && params[:unsub_all].blank?
      params[:frequency].each do |freq|
        @user.frequency << freq[0]
      end
    end

    params[:user].parse_time_select! :send_time
    if @user.update_without_password(devise_parameter_sanitizer.sanitize(:account_update))
      if @user.frequency.present?
        set_flash_message :notice, :updated
      else
        flash[:notice] = 'You are now unsubscribed from all emails.'
      end
    else
      set_flash_message :error, 'Could not update.'
    end

    redirect_to settings_path(@user.user_key)
  end

  private

  def track_ga_event
    return nil unless @user.id.present?
    Gabba::Gabba.new(ENV['GOOGLE_ANALYTICS_ID'], ENV['MAIN_DOMAIN']).event('User', 'Create', @user.user_key) if ENV['GOOGLE_ANALYTICS_ID'].present?
  end

  # check if we need password to update user data
  # ie if password or email was changed
  # extend this as needed
  def needs_password?(user, params)
    user.email != user_params[:email] ||
      user_params[:password].present? ||
      user_params[:password_confirmation].present?
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :send_time, :send_timezone, :send_past_entry, :email, :password, :password_confirmation)
  end
end
