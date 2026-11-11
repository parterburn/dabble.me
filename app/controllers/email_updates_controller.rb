# The unsubscribe link in product-update emails. No login: the signed token
# from the email names the account, the same one the settings links use.
#
# GET shows a page with a button, so a link scanner following the link
# unsubscribes no one. POST unsubscribes; mailbox providers send it directly
# for one-click unsubscribe (RFC 8058), without cookies or a CSRF token.
class EmailUpdatesController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :destroy
  before_action :find_user

  def show; end

  def destroy
    @user.update_columns(send_updates: false)
    render :unsubscribed
  end

  private

  def find_user
    @user = User.find_by_token_for(:email_settings, params[:token].to_s)
    return if @user

    redirect_to new_user_session_path, alert: "That link no longer works. Log in to change your email settings."
  end
end
