class RegistrationsController < Devise::RegistrationsController

  def new
    if ENV['CLOSE_REGISTRATIONS'].present?
      flash[:notice] = 'Registrations are not open; enter your email below to be alerted!'
      redirect_to root_path
    else
      super
    end
  end

  def create
    if ENV['CLOSE_REGISTRATIONS'].present?
      flash[:notice] = 'Registrations are not open; enter your email below to be alerted!'
      redirect_to root_path
    else
      super
    end
  end

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

    successfully_updated = if needs_password?(@user, params)
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
      sign_in @user, :bypass => true
      redirect_to edit_user_registration_path
    else
      redirect_to edit_user_registration_path
    end
  end
  

  private

  # check if we need password to update user data
  # ie if password or email was changed
  # extend this as needed
  def needs_password?(user, params)
    user.email != params[:user][:email] ||
      params[:user][:password].present? ||
      params[:user][:password_confirmation].present?
  end

end