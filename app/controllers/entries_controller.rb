class EntriesController < ApplicationController
  before_action :authenticate_user!
  before_filter :require_permission, only: [:show, :edit, :update, :destroy]

  def index
    if params[:group] == 'photos'
      @entries = current_user.entries.includes(:inspiration).only_images
      @title = ActionController::Base.helpers.pluralize(@entries.count, 'entry') + ' with photos'
    elsif params[:group] =~ /[0-9]{4}/ && params[:subgroup] =~ /[0-9]{2}/
      @entries = current_user.entries.includes(:inspiration).where("date >= to_date('#{params[:group]}-#{params[:subgroup]}','YYYY-MM') AND date < to_date('#{params[:group]}-#{params[:subgroup].to_i + 1}','YYYY-MM')")
      date = Date.parse(params[:subgroup] + '/' + params[:group])
      @title = ActionController::Base.helpers.pluralize(@entries.count, 'entry') + " from #{date.strftime('%b %Y')}"
    elsif params[:group] =~ /[0-9]{4}/
      @entries = current_user.entries.includes(:inspiration).where("date >= '#{params[:group]}-01-01'::DATE AND date <= '#{params[:group]}-12-31'::DATE")
      @title = ActionController::Base.helpers.pluralize(@entries.count, 'entry') + " from #{params[:group]}"
    else
      @entries = current_user.entries.includes(:inspiration)
      @title = ActionController::Base.helpers.pluralize(@entries.count, 'entry') + ' from All Time'
    end

    @entries = Kaminari.paginate_array(@entries).page(params[:page]).per(params[:per])

    respond_to do |format|
      format.json { render json: calendar_json(current_user.entries.where("date >= '#{params[:start]}'::DATE AND date < '#{params[:end]}'::DATE")) }
      format.html
    end
  end

  def show
    @entry = Entry.includes(:inspiration).find(params[:id])
    if @entry
      render 'show'
    else
      redirect_to past_entries_path
    end
  end

  def random
    @entry = current_user.random_entry
    if @entry
      render 'show'
    else
      redirect_to past_entries_path
    end
  end

  def new
    @entry = Entry.new
    @random_inspiration = random_inspiration
  end

  def calendar
  end

  def create
    @user = current_user
    @existing_entry = @user.existing_entry(params[:entry][:date].to_s)

    if @existing_entry.present? && params[:entry][:entry].present?
      @existing_entry.body += "<hr>#{params[:entry][:entry]}"
      @existing_entry.inspiration_id = params[:entry][:inspiration_id] if params[:entry][:inspiration_id].present?
      if params[:entry][:image_url].present? && @existing_entry.image_url.present?
        img_url_cdn = params[:entry][:image_url].gsub('https://www.filepicker.io', ENV['FILEPICKER_CDN_HOST'])
        @existing_entry.body += "<br><div class='pictureFrame'><a href='#{img_url_cdn}' target='_blank'><img src='#{img_url_cdn}/convert?fit=max&w=300&h=300&cache=true&rotate=:exif' alt='#{@existing_entry.date.strftime('%b %-d')}'></a></div>"
      elsif params[:entry][:image_url].present?
        @existing_entry.image_url = params[:entry][:image_url]
      end
      if @existing_entry.save
        flash[:notice] = "Merged with existing entry on #{@existing_entry.date.strftime("%B %-d")}. <a href='#entry-#{@existing_entry.id}' data-id='#{@existing_entry.id}' class='alert-link j-entry-link'>View merged entry</a>.".html_safe
        redirect_to group_entries_path(@existing_entry.date.strftime('%Y'), @existing_entry.date.strftime('%m'))
      else
        render 'new'
      end
    else
      @entry = @user.entries.create(entry_params)
      if @entry.save
        flash[:notice] = "Entry created successfully! <a href='#entry-#{@entry.id}' data-id='#{@entry.id}' class='alert-link j-entry-link'>View entry</a>.".html_safe
        redirect_to group_entries_path(@entry.date.strftime('%Y'), @entry.date.strftime('%m'))
      else
        render 'new'
      end
    end
  end

  def edit
    store_location
    @entry = Entry.find(params[:id])
    if current_user.is_free?
      @entry.body = @entry.sanitized_body
    end
  end

  def update
    @entry = Entry.find(params[:id])
    @existing_entry = current_user.existing_entry(params[:entry][:date].to_s)

    if @existing_entry.present? && @entry != @existing_entry && params[:entry][:entry].present?
      #existing entry exists, so add to it
      @existing_entry.body += "<hr>#{params[:entry][:entry]}"
      @existing_entry.inspiration_id = params[:entry][:inspiration_id] if params[:entry][:inspiration_id].present?
      if params[:entry][:image_url].present? && @existing_entry.image_url.present?
        img_url_cdn = params[:entry][:image_url].gsub("https://www.filepicker.io", ENV['FILEPICKER_CDN_HOST'])
        @existing_entry.body += "<br><div class='pictureFrame'><a href='#{img_url_cdn}' target='_blank'><img src='#{img_url_cdn}/convert?fit=max&w=300&h=300&cache=true&rotate=:exif' alt='#{@existing_entry.date.strftime("%b %-d")}'></a></div>"        
      elsif params[:entry][:image_url].present?
        @existing_entry.image_url = params[:entry][:image_url]
      end
      if @existing_entry.save
        @entry.delete
        flash[:notice] = "Merged with existing entry on #{@existing_entry.date.strftime("%B %-d")}. <a href='#entry-#{@existing_entry.id}' data-id='#{@existing_entry.id}' class='alert-link j-entry-link'>View merged entry</a>.".html_safe
        redirect_to group_entries_path(@existing_entry.date.strftime("%Y"),@existing_entry.date.strftime("%m")) and return
      else
        render 'edit'
      end
    elsif params[:entry][:entry].blank?
      @entry.destroy
      flash[:notice] = 'Entry deleted!'
      redirect_back_or_to past_entries_path
    else
      if @entry.update(entry_params)
        flash[:notice] = "Entry successfully updated! <a href='#entry-#{@entry.id}' data-id='#{@entry.id}' class='alert-link j-entry-link'>View entry</a>.".html_safe
        redirect_to group_entries_path(@entry.date.strftime("%Y"),@entry.date.strftime("%m"))
      else
        render 'edit'
      end
    end
  end

  def destroy
    @entry = Entry.find(params[:id])
    @entry.destroy
    flash[:notice] = 'Entry deleted successfully.'
    redirect_to past_entries_path
  end

  def export
    @entries = current_user.entries.sort_by(&:date)
    respond_to do |format|
      format.json { send_data JSON.pretty_generate(JSON.parse(@entries.to_json(:only => [:date, :body, :image_url]))), :filename => "export_#{Time.now.strftime("%Y-%m-%d")}.json" }
      format.txt do
        response.headers['Content-Type'] = 'text/txt'
        response.headers['Content-Disposition'] = "attachment; filename=export_#{Time.now.strftime("%Y-%m-%d")}.txt"
        render 'text_export'
      end
      format.zip do
        download_manifest = photo_files
        zip_up(download_manifest)
      end
    end
  end

  private

  def entry_params
    params.require(:entry).permit(:date, :entry, :image_url, :inspiration_id)
  end

  def require_permission
    return false if current_user == Entry.find(params[:id]).user
    flash[:alert] = 'Not authorized'
    redirect_to past_entries_path
  end

  def random_inspiration
    count = Inspiration.without_ohlife_or_email.count
    return nil if count == 0
    Inspiration.without_ohlife_or_email.offset(rand(count)).first
  end

  def photo_files
    photo_entries = current_user.entries.only_images
    files_to_zip = []

    # photo_entries.each do |entry|
    #   if entry.image_url.present?
    #     ext = fetch_extension(entry.image_url.scan(/\/api\/file\/([A-Za-z0-9]*)/).first.first)
    #     files_to_zip << { path: "Dabble Me Photos/img_#{entry.date.strftime('%Y-%m-%d')}-0.#{ext}", url: "#{URI.encode(entry.image_url)}" }
    #   end
    #   entry.body.scan(/"https\:\/\/d3bcnng5dpbnbb.cloudfront.net\/api\/file\/[A-Za-z0-9]*"/).each_with_index do |img_url, index|
    #     img_url.gsub!('"', '')
    #     ext = fetch_extension(img_url.scan(/\/api\/file\/([A-Za-z0-9]*)/).first.first)
    #     files_to_zip << { path: "Dabble Me Photos/img_#{entry.date.strftime('%Y-%m-%d')}-#{index+1}.#{ext}", url: "#{URI.encode(img_url)}" }
    #   end
    # end
    { name: "export_#{Time.now.strftime('%Y-%m-%d')}", files: files_to_zip.compact }
  end

  def zip_up(download_manifest)
    response =  HTTParty.post "http://#{ENV['DOWNLOADER_URL']}/downloads",
                              headers: { 'Content-Type' => 'application/json' },
                              basic_auth: {
                                username: ENV['DOWNLOADER_ID'],
                                password: ENV['DOWNLOADER_SECRET']
                              },
                              body: download_manifest.to_json
    redirect_to response['url']
    rescue
      flash[:alert] = 'Could not download ZIP file.'
      redirect_to edit_user_registration_path
  end

  def fetch_extension(filepicker_id)
    response = Net::HTTP.start(ENV['FILEPICKER_CDN_HOST'].gsub('https://', '')) do |http|
      http.open_timeout = 2
      http.read_timeout = 2
      http.head("/api/file/#{filepicker_id}")
    end
    response['content-type'].gsub('image/', '')
  end

  def calendar_json(entries)
    return false unless current_user.is_pro?
    json_hash = []
    entries.each do |entry|
      json_hash <<  {
        id: entry.id,
        title: entry.sanitized_body.gsub(/\n/, '').truncate(100, separator: ' '),
        url: entry_path(entry),
        start: entry.date.strftime('%Y-%m-%d'),
        allDay: 'true'
      }
    end
    json_hash.to_json
  end
end
