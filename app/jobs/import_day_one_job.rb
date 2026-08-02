# frozen_string_literal: true

class ImportDayOneJob < ActiveJob::Base
  queue_as :default

  def perform(user_id, stored_path)
    @user = User.find(user_id)
    result = DayOneImporter.new(user: @user, zip_path: stored_path).import!
    deliver_completion_email(result)
  rescue StandardError => e
    Sentry.capture_exception(e, extra: { user_id: user_id, stored_path: stored_path })
    deliver_failure_email(e)
  ensure
    ImportUploadStore.cleanup!(stored_path)
  end

  private

  def deliver_completion_email(result)
    parts = []
    parts << "Finished importing #{ActionController::Base.helpers.pluralize(result.imported, 'entry')} from Day One."
    parts << "You can view them at #{::Rails.application.routes.url_helpers.entries_url}."

    if result.skipped.present?
      Sentry.capture_message("Day One import skipped entries", level: :info, extra: { skipped: result.skipped, user_id: @user.id })
      parts << "Skipped: #{result.skipped.join('; ')}."
    end

    if result.errors.present?
      Sentry.capture_message("Day One import errors", level: :info, extra: { errors: result.errors, user_id: @user.id })
      parts << "Errors: #{result.errors.join('; ')}."
    end

    ActionMailer::Base.mail(
      from: "Paul from Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>",
      to: @user.email,
      subject: "Import of Day One entries is complete",
      content_type: "text/html",
      body: parts.join(" ")
    ).deliver_later
  end

  def deliver_failure_email(error)
    return unless @user

    ActionMailer::Base.mail(
      from: "Paul from Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>",
      to: @user.email,
      subject: "Day One import failed",
      content_type: "text/html",
      body: "Your Day One import could not be completed (#{error.message}). Please try again with a Day One JSON ZIP export, or reply to this email for help."
    ).deliver_later
  end
end
