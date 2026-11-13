# The Export page, and the pages an "export is ready" email leads to. Signing
# in is required, and an export is only ever shown to the person it belongs
# to, so the email alone is not enough to get the file.
class ExportsController < ApplicationController
  before_action :authenticate_user!
  before_action :find_export, only: %i[show download]
  before_action :set_subset, only: %i[new create]

  # The Export page. With .md, the journal as Markdown, streamed right away.
  def new
    return stream_markdown if request.format.md?

    @years = current_user.entries.unscope(:order).distinct.pluck(Arel.sql("extract(year from date)::int")).sort.reverse
    @recent_exports = current_user.exports.where(created_at: Export::LIFETIME.ago..).order(created_at: :desc).limit(5).select(&:downloadable?)
    render :new, formats: [:html]
  end

  # Starts a ZIP (ExportEntriesJob): the journal as a web page and as
  # Markdown, plus photos. Asking for the same ZIP again inside
  # Export::LIMIT_PERIOD downloads the last one. download=markdown streams
  # the Markdown instead, so the page's one form serves both buttons.
  def create
    return stream_markdown if params[:download] == "markdown"

    scope = Export.scope_for(year: @year, search_term: @search_term)
    back = export_entries_path({ year: @year, search: (@search_term && { term: @search_term }) }.compact)
    recent = current_user.exports.within_limit.where(scope: scope).order(:created_at).last
    if recent&.preparing?
      redirect_to back, notice: "Your export is already being prepared. We'll email you a link when it's ready."
    elsif recent&.downloadable?
      redirect_to download_export_path(recent)
    elsif current_user.exports.where(created_at: 1.hour.ago..).count >= Export::HOURLY_LIMIT
      redirect_to back, alert: "You've requested a lot of exports in the last hour. Please try again later."
    else
      export = current_user.exports.create!(scope: scope, search_term: @search_term)
      ExportEntriesJob.perform_later(export.id)
      redirect_to back, notice: "Your export is being prepared. We'll email you a link to download it. The link works for 7 days."
    end
  end

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

  # What to export: one year, the entries matching a search, or everything.
  def set_subset
    @search_term = params.dig(:search, :term).to_s.strip.presence
    @year = params[:year].presence
    return unless @year && @year !~ /\A(19|20)\d{2}\z/

    redirect_to export_entries_path, alert: "That year doesn't look right. Pick one from the list."
  end

  def stream_markdown
    entries = if @search_term
                Search.new(term: @search_term, user: current_user).entries
              elsif @year
                current_user.entries.where(date: Time.utc(@year.to_i).all_year)
              else
                current_user.entries
              end
    name = Export.file_stem(year: @year, search_term: @search_term)

    headers["Content-Type"] = "text/markdown; charset=utf-8"
    headers["Content-Disposition"] = %(attachment; filename="#{name}.md")
    headers["Cache-Control"] = "no-store"
    # Rack::ETag would read the whole body to hash it; this stops it.
    headers["Last-Modified"] = Time.current.httpdate
    self.response_body = ExportMarkdown.stream(entries, description: Export.describe(year: @year, search_term: @search_term))
  end

  def find_export
    @export = current_user.exports.find_by(token: params[:token].to_s)
    return if @export

    redirect_to export_entries_path, alert: "That export wasn't found. You can request a new one here."
  end
end
