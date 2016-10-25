# Handle Web Entries
class EntriesController < ApplicationController
  before_action :authenticate_user!
  before_filter :set_entry, :require_entry_permission, only: [:show, :edit, :update, :destroy]

  def index
    if params[:group] == 'photos'
      @entries = current_user.entries.includes(:inspiration).only_images
      @title = 'Photo Entries'
    elsif params[:subgroup].present?
      from_date = "#{params[:group]}-#{params[:subgroup]}"
      to_date = "#{params[:group]}-#{params[:subgroup].to_i + 1}"
      @entries = current_user.entries.includes(:inspiration).where("date >= to_date('#{from_date}','YYYY-MM') AND date < to_date('#{to_date}','YYYY-MM')").sort_by(&:date)
      date = Date.parse(params[:subgroup] + '/' + params[:group])
      @title = "Entries from #{date.strftime('%b %Y')}"
    elsif params[:group].present?
      begin
        raise 'not a year' unless params[:group] =~ /(19|20)[0-9]{2}/
        @entries = current_user.entries.includes(:inspiration).where("date >= '#{params[:group]}-01-01'::DATE AND date <= '#{params[:group]}-12-31'::DATE").sort_by(&:date)
      rescue
        entry = current_user.entries.find(params[:group])
        return redirect_to day_entry_path(year: entry.date.year, month: entry.date.month, day: entry.date.day)
      end
      @title = "Entries from #{params[:group]}"
    else
      @entries = current_user.entries.includes(:inspiration)
      @title = 'All Entries'
    end

    @entries = Kaminari.paginate_array(@entries).page(params[:page]).per(params[:per])

    redirect_to latest_entry_path and return if @entries.blank?

    respond_to do |format|
      format.json {
        render json: calendar_json(current_user.entries
          .where("date >= '#{params[:start]}'::DATE AND date < '#{params[:end]}'::DATE")) }
      format.html
    end
  end

  def show
    if @entry
      track_ga_event('Show')
      render 'show'
    else
      redirect_to entries_path
    end
  end

  def latest
    @lastest_entry = current_user.entries.includes(:inspiration).sort_by(&:date).last
  end

  def random
    @entry = current_user.random_entry
    if @entry
      track_ga_event('Random')
      render 'show'
    else
      redirect_to entries_path
    end
  end

  def new
    @entry = Entry.new
    @random_inspiration = random_inspiration
  end

  def calendar
  end

  def create
    if current_user.is_free?
      flash[:alert] = "<a href='#{subscribe_url}'' class='alert-link'>Subscribe to PRO</a> to write new entries.".html_safe
      redirect_to root_path and return
    end

    @existing_entry = current_user.existing_entry(params[:entry][:date].to_s)

    if @existing_entry.present? && params[:entry][:entry].present?
      @existing_entry.body += "<hr>#{params[:entry][:entry]}"
      @existing_entry.inspiration_id = params[:entry][:inspiration_id] if params[:entry][:inspiration_id].present?
      if @existing_entry.image_url_cdn.blank? && params[:entry][:image].present?
        @existing_entry.image = params[:entry][:image]
      end
      if @existing_entry.save
        flash[:notice] = "Merged with existing entry on #{@existing_entry.date.strftime("%B %-d")}."
        track_ga_event('Merged')
        redirect_to day_entry_path(year: @existing_entry.date.year, month: @existing_entry.date.month, day: @existing_entry.date.day)
      else
        render 'new'
      end
    else
      @entry = current_user.entries.create(entry_params)
      if @entry.save
        track_ga_event('New')
        flash[:notice] = "Entry created successfully!"
        redirect_to day_entry_path(year: @entry.date.year, month: @entry.date.month, day: @entry.date.day)
      else
        render 'new'
      end
    end
  end

  def edit
    store_location
    if current_user.is_free?
      @entry.body = @entry.sanitized_body
    end
    track_ga_event('Edit')
  end

  def update
    if current_user.is_free?
      flash[:alert] = "<a href='#{subscribe_url}'' class='alert-link'>Subscribe to PRO</a> to edit entries.".html_safe
      redirect_to root_path and return
    end

    @existing_entry = current_user.existing_entry(params[:entry][:date].to_s)

    if @entry.present? && @existing_entry.present? && @entry != @existing_entry && params[:entry][:entry].present?
      # existing entry exists, so add to it
      @existing_entry.body += "<hr>#{params[:entry][:entry]}"
      @existing_entry.inspiration_id = params[:entry][:inspiration_id] if params[:entry][:inspiration_id].present?
      if @existing_entry.image_url_cdn.blank? && params[:entry][:image].present?
        @existing_entry.image = params[:entry][:image]
      end
      if @existing_entry.save
        @entry.delete
        flash[:notice] = "Merged with existing entry on #{@existing_entry.date.strftime('%B %-d')}."
        track_ga_event('Update')
        redirect_to day_entry_path(year: @existing_entry.date.year, month: @existing_entry.date.month, day: @existing_entry.date.day) and return
      else
        render 'edit'
      end
    elsif params[:entry][:entry].blank?
      @entry.destroy
      flash[:notice] = 'Entry deleted!'
      redirect_back_or_to entries_path
    else
      if @entry.update(entry_params)
        track_ga_event('Update')
        flash[:notice] = "Entry successfully updated!"
        redirect_to day_entry_path(year: @entry.date.year, month: @entry.date.month, day: @entry.date.day)
      else
        render 'edit'
      end
    end
  end

  def destroy
    if current_user.is_free?
      flash[:alert] = "<a href='#{subscribe_url}'' class='alert-link'>Subscribe to PRO</a> to edit entries.".html_safe
      redirect_to root_path and return
    end

    @entry.destroy
    track_ga_event('Delete')
    flash[:notice] = 'Entry deleted successfully.'
    redirect_to entries_path
  end

  def export
    @entries = current_user.entries.sort_by(&:date)
    track_ga_event('Export')
    respond_to do |format|
      format.json { send_data JSON.pretty_generate(JSON.parse(@entries.to_json(only: [:date, :body, :image_url_cdn]))), filename: "export_#{Time.now.strftime('%Y-%m-%d')}.json" }
      format.txt do
        response.headers['Content-Type'] = 'text/txt'
        response.headers['Content-Disposition'] = "attachment; filename=export_#{Time.now.strftime('%Y-%m-%d')}.txt"
        render 'text_export'
      end
    end
  end

  def review
    @year = 2016
    @entries = current_user.entries.where("date >= '#{@year}-01-01'::DATE AND date <= '#{@year}-12-31'::DATE")
    @total_count = @entries.count
    if @total_count > 0
      @body_text = @entries.pluck(:body).join()
      @words_counter = WordsCounted.count(@body_text, exclude: ['p', 'br', 'div', 'img'])
    else
      flash[:notice] = 'No entries in 2016 - nothing to review :('
      redirect_to entries_path
    end

    # Stats for 2015
    # 1,703 users
    # 33,364 entries
    # 5,017,056 total words
    # 150.4 avg words
    # 28,602,926 characters
    # 857.30 avg characters per post (6.1 tweets)
    # 171,919 were the word "I"
  end

  private

  def track_ga_event(action)
    Gabba::Gabba.new(ENV['GOOGLE_ANALYTICS_ID'], ENV['MAIN_DOMAIN']).event('Web Entry', action, current_user.user_key) if ENV['GOOGLE_ANALYTICS_ID'].present?
  end

  def entry_params
    params.require(:entry).permit(:date, :entry, :image, :inspiration_id, :remove_image)
  end

  def set_entry
    if params[:day].present?
      date = Date.parse("#{params[:year]}-#{params[:month]}-#{params[:day]}")
      @entry = current_user.entries.includes(:inspiration).where(date: date).first
    else
      @entry = current_user.entries.includes(:inspiration).where(id: params[:id]).first
    end
  end

  def require_entry_permission
    return false if @entry.present? && current_user == @entry.user
    flash[:alert] = 'Not authorized'
    redirect_to entries_path
  end

  def random_inspiration
    count = Inspiration.without_imports_or_email.count
    return nil if count == 0
    Inspiration.without_imports_or_email.offset(rand(count)).first
  end

  def calendar_json(entries)
    return false unless current_user.is_pro?
    json_hash = []
    entries.each do |entry|
      json_hash <<  {
        id: entry.id,
        title: entry.sanitized_body.gsub(/\n/, '').truncate(100, separator: ' '),
        url: day_entry_path(year: entry.date.year, month: entry.date.month, day: entry.date.day),
        start: entry.date.strftime('%Y-%m-%d'),
        allDay: 'true'
      }
    end
    json_hash.to_json
  end
end
