require 'fileutils'

class ImportController < ApplicationController
  before_action :authenticate_user!
  SPLIT_AT_DATE_REGEX = /[12]{1}[90]{1}[0-9]{2}\-[0-1]{1}[0-9]{1}\-[0-3]{1}[0-9]{1}/

  def update
    if current_user.is_free?
      flash[:alert] = "<a href='#{subscribe_path}' class='alert-link'>Subscribe to PRO</a> to import entries.".html_safe
      redirect_to import_path and return
    end

    if params[:type]&.downcase == "ahhlife"
      import_ahhlife_entries(params[:entry][:text])
    elsif params[:type]&.downcase == "trailmix"
      enqueue_trailmix_import
    else
      import_ohlife_entries(params[:entry][:text])
    end
  end

  def process_ohlife_images
    if current_user.is_free?
      flash[:alert] = "<a href='#{subscribe_path}' class='alert-link'>Subscribe to PRO</a> to import entries.".html_safe
      redirect_to import_path and return
    end

    begin
      stored_path = ImportUploadStore.store!(
        uploaded_file: params[:zip_file],
        user_key: current_user.user_key,
        kind: "ohlife"
      )
      ImportJob.perform_later(current_user.id, stored_path)
      flash[:notice] = "Photo Import has started."
      redirect_to entries_path
    rescue ImportUploadStore::Error => e
      FileUtils.rm_f(params[:zip_file]&.tempfile&.path) if params[:zip_file]
      flash[:alert] = e.message
      redirect_to import_path(type: "photos")
    end
  end

  def process_trailmix_entries
    data = params[:entry][:text]
    import_trailmix_entries(data)
  rescue JSON::ParserError, NoMethodError => e
    flash[:alert] = "Invalid JSON Format: #{e.message}"
    redirect_to import_path(type: "trailmix")
  end

  private

  def enqueue_trailmix_import
    stored_path = ImportUploadStore.store!(
      uploaded_file: params[:json_file],
      user_key: current_user.user_key,
      kind: "trailmix"
    )
    ImportTrailmixJob.perform_later(current_user.id, stored_path)
    flash[:notice] = "Import has started. You will receive an email when it is finished."
    redirect_to entries_path
  rescue ImportUploadStore::Error => e
    FileUtils.rm_f(params[:json_file]&.tempfile&.path) if params[:json_file]
    flash[:alert] = e.message
    redirect_to import_path(type: "trailmix")
  end

  def import_ohlife_entries(data)
    errors = []
    user = current_user

    dates = data.scan(SPLIT_AT_DATE_REGEX)
    bodies  = data.split(SPLIT_AT_DATE_REGEX)
    bodies.shift

    dates.each_with_index do |date, i|
      body = ActionController::Base.helpers.simple_format(bodies[i])
      body.gsub!(/\A(\<p\>\<\/p\>)/, '')
      body.gsub!(/(\<p\>\<\/p\>)\z/, '')
      entry = user.entries.create(date: date, body: body, inspiration_id: 1)
      unless entry.save
        errors << date
      end
    end

    flash[:notice] = 'Finished importing ' + ActionController::Base.helpers.pluralize(dates.count, 'entry')

    return flash unless errors.present?

    flash[:alert] = '<strong>' + ActionController::Base.helpers.pluralize(errors.count, 'error') + ' while importing:</strong>'
    errors.each do |error|
      flash[:alert] << '<br>' + error
    end
  end

  def import_ahhlife_entries(data)
    errors = []
    user = current_user

    j_data = JSON.parse(data)
    i = 0;
    j_data.each do |s|
      s.second.each do |e|
        i += 1
        entry = e.second
        body = ActionController::Base.helpers.simple_format(entry['content'])
        body.gsub!(/\A(\<p\>\<\/p\>)/, '')
        body.gsub!(/(\<p\>\<\/p\>)\z/, '')
        date = Time.at(entry['timestamp']/1000).utc
        entry = user.entries.create(date: date, body: body, inspiration_id: 59)
        unless entry.save
          errors << date
        end
      end
    end

    if errors.present?
      flash[:alert] = '<strong>' + ActionController::Base.helpers.pluralize(errors.count, 'error') + ' while importing:</strong>'
      errors.each do |error|
        flash[:alert] << '<br>' + error
      end
      redirect_to import_path(type: "ahhlife")
    else
      flash[:notice] = 'Finished importing ' + ActionController::Base.helpers.pluralize(i, 'entry')
      redirect_to entries_path
    end
  rescue JSON::ParserError, NoMethodError => e
    flash[:alert] = "Invalid JSON Format: #{e.message}"
    redirect_to import_path(type: "ahhlife")
  end
end
