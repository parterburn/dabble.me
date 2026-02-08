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
      tmp = params[:json_file]
      dir = FileUtils.mkdir_p("public/trailmix_zips/#{current_user.user_key}")
      file = File.join(dir, tmp.original_filename)
      FileUtils.mv tmp.tempfile.path, file
      ImportTrailmixJob.perform_later(current_user.id, tmp.original_filename)
      flash[:notice] = "Import has started. You will receive an email when it is finished."
      redirect_to entries_path
    else
      import_ohlife_entries(params[:entry][:text])
    end
  end

  def process_ohlife_images
    tmp = params[:zip_file]
    if tmp && File.extname(tmp.original_filename).downcase == ".zip"

      #move uploaded ZIP file to /tmp/ohlife_zips
      dir = FileUtils.mkdir_p("public/ohlife_zips/#{current_user.user_key}")
      file = File.join(dir, tmp.original_filename)
      FileUtils.mv tmp.tempfile.path, file

      ImportJob.perform_later(current_user.id, tmp.original_filename)
      flash[:notice] = "Photo Import has started."
      redirect_to entries_path
    else
      FileUtils.rm tmp.tempfile.path if tmp
      flash[:alert] = "Only ZIP files are allowed here."
      redirect_to import_path
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
