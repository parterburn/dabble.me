# Devise Override Controller
class RegistrationsController < Devise::RegistrationsController
  layout :choose_layout
  before_action :require_user, only: [:security, :delete_account, :update, :edit, :posting_address, :reset_posting_address]
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
      redirect_to delete_account_path, alert: "Account deletion has moved. Use the delete page to continue."
    else # updating
      if params[:frequency].present?
        user.frequency = params[:frequency].select { |day, value| value == "1" }.keys.map { |day| day[0..2] }
      end

      # Add validation for send_time
      if params[:user]["send_time(5i)"].present?
        params[:user].parse_time_select! :send_time
      else
        # Set a default time (e.g., 8:00 AM) if none provided
        params[:user]["send_time(5i)"] = "08:00:00"
        params[:user].parse_time_select! :send_time
      end

      successfully_updated = if needs_password?
        user.update_with_password(devise_parameter_sanitizer.sanitize(:account_update))
      else
        params[:user].delete(:current_password)
        user.update_without_password(devise_parameter_sanitizer.sanitize(:preferences))
      end

      if successfully_updated
        set_flash_message :notice, :updated
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
      schedule_user_deletion
      sign_out current_user
      redirect_to root_path, notice: "Your account will be permanently deleted in 1 hour. Sign back in before then to cancel deletion."
    else
      flash[:alert] = "Incorrect current password."
      redirect_to delete_account_path
    end
  end

  def delete_account
    render "devise/registrations/delete_account"
  end

  def security
    @oauth_applications = Doorkeeper::Application.authorized_for(current_user)
    render 'devise/registrations/security'
  end

  # Explains what a reset does and asks the user to confirm.
  def posting_address
    render 'devise/registrations/posting_address'
  end

  # Resets only after the user ticks the confirmation box. The check is
  # server-side so a reset can't happen without it, even if JavaScript or
  # the browser's required-field check is skipped.
  def reset_posting_address
    unless params[:confirm_reset] == '1'
      redirect_to posting_address_path, alert: 'Tick the box to confirm you want a new posting address.'
      return
    end

    current_user.rotate_user_key!
    UserMailer.posting_address_changed(current_user).deliver_later
    redirect_to edit_user_registration_path,
                notice: "Your new posting address is #{current_user.user_key}@#{ENV['SMTP_DOMAIN']}. Your old one no longer accepts entries."
  end

  def unsubscribe
    unless user
      redirect_to new_user_session_path, alert: 'That settings link no longer works. Log in to change your email settings.'
      return
    end

    if params[:frequency].present? && params[:unsub_all].blank?
      user.frequency = params[:frequency].select { |day, value| value == "1" }.keys.map { |day| day[0..2] }
    elsif params[:unsub_all].present?
      user.frequency = []
      user.send_updates = false
    end

    # Add validation for send_time
    if params[:user]["send_time(5i)"].present?
      params[:user].parse_time_select! :send_time
    else
      # Set a default time (e.g., 8:00 AM) if none provided
      params[:user]["send_time(5i)"] = "08:00:00"
      params[:user].parse_time_select! :send_time
    end

    prefs = devise_parameter_sanitizer.sanitize(:preferences).except(:email, :password, :password_confirmation, :current_password)
    prefs = prefs.except(:send_updates) if params[:unsub_all].present?
    if user.update_without_password(prefs)
      if user.frequency.present?
        set_flash_message :notice, :updated
      else
        flash[:notice] = 'You are now unsubscribed from all emails.'
      end
    else
      set_flash_message :error, 'Could not update.'
    end

    redirect_to settings_path(token: user.email_settings_token)
  end

  private

  def choose_layout
    if action_name == 'new' || action_name == 'create'
      'marketing'
    else
      'application'
    end
  end

  def schedule_user_deletion
    current_user.update_column(:deleted_at, Time.current)
    DeleteUserJob.set(wait: 1.hour).perform_later(current_user.id)
  end

  def check_captcha
    # Build the resource BEFORE the captcha check so that (a) the error we add
    # below actually sticks to something the view can render and (b) the form
    # re-renders with the values the user already typed.
    build_resource(sign_up_params)
    return true if valid_captcha?

    resource.errors.add(:base, "Couldn't verify that you're a human. Please complete the captcha below and try again.")
    clean_up_passwords(resource)
    flash.now[:alert] = "Captcha verification failed. Please try again."
    respond_with_navigational(resource) { render :new }
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
    @user ||= user_signed_in? ? current_user : user_from_email_link
  end

  # Settings links in emails carry ?token=. Emails sent before that put the
  # posting address in the path instead; those keep working until the user
  # resets their address. Drop the user_key lookup once those emails are old.
  def user_from_email_link
    if params[:token].present?
      User.find_by_token_for(:email_settings, params[:token])
    elsif params[:user_key].present?
      User.find_by(user_key: params[:user_key])
    end
  end
  helper_method :user

  def require_user
    return nil if user_signed_in?

    store_location_for(:user, request.fullpath)
    redirect_to new_user_session_path, alert: 'You must be logged in to access this page.'
  end
end
