# The "stop further notices" link in a service notice (ServiceNoticeMailer).
# No login: the signed token names the person's own copy of the notice.
#
# As with EmailUpdatesController, GET shows a page with a button, so a link
# scanner following the link stops nothing. POST records it; mailbox providers
# send it directly for one-click unsubscribe (RFC 8058), without cookies or a
# CSRF token.
class NoticeStopsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :create
  before_action :find_delivery

  def show; end

  def create
    @delivery.stop!
    render :stopped
  end

  private

  def find_delivery
    @delivery = ServiceNoticeDelivery.find_by_stop_token(params[:token])
    return if @delivery

    redirect_to root_path, alert: "That link no longer works."
  end
end
