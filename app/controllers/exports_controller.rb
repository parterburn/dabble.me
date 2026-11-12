# Where the link in an "export is ready" email leads. Signing in is required,
# and an export is only ever shown to the person it belongs to, so the email
# alone is not enough to get the file.
class ExportsController < ApplicationController
  before_action :authenticate_user!
  before_action :find_export

  def show; end

  # Hands over a link to the file that works for a few minutes.
  def download
    unless @export.downloadable?
      redirect_to export_path(@export), alert: "This export is no longer available."
      return
    end

    @export.downloaded!
    url = ExportStore.new.download_url(@export.storage_key, filename: @export.filename,
                                                            expires_at: Export::LINK_LIFETIME.from_now)
    redirect_to url, allow_other_host: true
  end

  private

  def find_export
    @export = current_user.exports.find_by(token: params[:token].to_s)
    return if @export

    redirect_to edit_user_registration_path(anchor: "export"), alert: "That export wasn't found. You can request a new one here."
  end
end
