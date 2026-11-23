# The Sessions section of Account Security: sign one device out, or every other one.
class SignedInDevicesController < ApplicationController
  include Devise::Controllers::Rememberable
  before_action :authenticate_user!

  # DELETE /security/sessions/:id
  def destroy
    session_row = current_user.user_sessions.find(params[:id])
    if session_row.id == Current.user_session&.id
      sign_out(current_user)
      redirect_to new_user_session_path, notice: 'You signed out of this device.'
    else
      session_row.revoke!
      redirect_to security_path(anchor: 'sessions'), notice: "Signed out #{session_row.device_label}."
    end
  end

  # DELETE /security/sessions: every browser and app but this one.
  def destroy_all
    current_user.sign_out_everywhere!(keep: Current.user_session)
    current_user.reload
    # The salt changed: store the new one so this browser stays signed in (and remembered).
    bypass_sign_in(current_user, scope: :user)
    remember_me(current_user)
    redirect_to security_path(anchor: 'sessions'), notice: 'Signed out of all other devices.'
  end
end
