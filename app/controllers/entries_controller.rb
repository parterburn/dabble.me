class EntriesController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:incoming]  
  before_action :authenticate_user!, except: [:incoming]
  before_filter :require_permission, only: [:show, :edit, :update, :destroy]

  def index
    begin
      if params[:year].present? && params[:month].present?
        @entries = Entry.where(:user_id => current_user).where("date >= to_date('#{params[:year]}-#{params[:month]}','YYYY-MM') AND date < to_date('#{params[:year]}-#{params[:month].to_i+1}','YYYY-MM')").sort_by(&:date).reverse
        date = Date.parse(params[:month]+'/'+params[:year])
        @title = "#{date.strftime('%b %Y')}"      
      elsif params[:year].present?
        @entries = Entry.where(:user_id => current_user).where("date >= '#{params[:year]}-01-01'::DATE AND date <= '#{params[:year]}-12-31'::DATE").sort_by(&:date).reverse
        @title = "#{params[:year]}"
      else
        ActionController::ShowAllEntries
      end
    rescue
      @entries = Entry.where(:user_id => current_user).sort_by(&:date).reverse
      @title = "All Time"
    end
  end

  def show
    @entry = Entry.find(params[:id])
    if @entry
      render "show"
    else
      redirect_to entries_path
    end
  end

  def random
    if (count = Entry.where(:user_id => current_user).count) > 0
      offset = rand(count)
      @entry = Entry.where(:user_id => current_user).offset(offset).first
      render "show"
    else
      redirect_to entries_path
    end
  end  

  def new
    @entry = Entry.new
  end

  def create
    @user = current_user

    #check for existing entry
    begin
      selected_date = Date.parse(params[:entry][:date])
      @existing_entry = Entry.where(:user_id => @user.id, :date => selected_date.beginning_of_day..selected_date.end_of_day).first
    rescue
    end

    p "*"*100
    p @existing_entry
    p params[:entry][:entry]
    p "*"*100
      
    if @existing_entry.present? && params[:entry][:entry].present?
      #existing entry exists, so add to it
      @existing_entry.body += "<br><br>--------------------------------<br><br>#{params[:entry][:entry]}"
      if params[:entry][:image_url].present? && @existing_entry.image_url.present?
        @existing_entry.body += "<br>Image: #{params[:entry][:image_url]}"
      elsif params[:entry][:image_url].present?
        @existing_entry.image_url = params[:entry][:image_url]
      end
      if @existing_entry.save
        flash[:notice] = "Merged with existing entry on #{selected_date}."
        redirect_to @existing_entry
      else
        #errors
        render 'new'
      end
    else
      @entry = @user.entries.create(entry_params)
      if @entry.save
        #save new entry & view it
        flash[:notice] = "Entry created successfully!"
        redirect_to @entry
      else
        #errors
        render 'new'
      end
    end
  end

def incoming
  #https://sendgrid.com/blog/two-hacking-santas-present-rails-the-inbound-parse-webhook/
  p "*"*100
  p "ENVELOPE PARAMS: #{params["envelope"]}"
  p "FROM: #{JSON.parse(params["envelope"])["from"]}"
  p "TO: #{params['to']}"
  p "SUBJECT: #{params['subject']}"
  p "TEXT: #{params['text']}"
  p "HTML: #{params['html']}"
  p "*"*100
  begin 
    from_email = JSON.parse(params["envelope"])["from"]
    user = User.find_by_email(from_email)
  rescue JSON::ParserError => e
  end

  if user.present?
    date_regex = /[201]{3}[0-4]{1}-[0-1]{1}[0-9]{1}-[0-3]{1}[0-9]{1}/
    date = params['to'].scan(date_regex)
    p "*"*100
    p "DATE: #{date}"
    p "*"*100
    entry = user.entries.create(:date => date, :body => params['text'], :inspiration_id => 2)
    if entry.save
      render :json => { "message" => "RIGHT" }, :status => 200
    else
      render :json => { "message" => "ERROR" }, :status => 200
    end 
  else
    render :json => { "message" => "NO USER" }, :status => 200
  end
end

  def edit
    @entry = Entry.find(params[:id])
  end

  def update
    @entry = Entry.find(params[:id])

    #check for existing entry
    begin
      selected_date = Date.parse(params[:entry][:date])
      @existing_entry = Entry.where(:user_id => current_user.id, :date => selected_date.beginning_of_day..selected_date.end_of_day).first
    rescue
    end

    if @existing_entry.present? && @entry != @existing_entry && params[:entry][:entry].present?
      #existing entry exists, so add to it
      @existing_entry.body += "<br>--------------------------------<br>#{params[:entry][:entry]}"
      if params[:entry][:image_url].present? && @existing_entry.image_url.present?
        @existing_entry.body += "<br>Image: #{params[:entry][:image_url]}"
      elsif params[:entry][:image_url].present?
        @existing_entry.image_url = params[:entry][:image_url]
      end
      if @existing_entry.save
        @entry.delete
        flash[:notice] = "Merged with existing entry on #{selected_date}."
        redirect_to @existing_entry
      else
        render 'edit'        
      end
    else
      if @entry.update(entry_params)
        flash[:notice] = "Entry successfully updated!"
        redirect_to @entry
      else
        render 'edit'
      end
    end

  end

  def destroy
    @entry = Entry.find(params[:id])
    @entry.destroy
    flash[:notice] = "Entry deleted successfully."
    redirect_to entries_path
  end

  def import
  end

  def process_import
    flash = import_ohlife_entries(params[:entry][:text])
    redirect_to entries_path
  end

  def export
    entries = Entry.where(:user_id => current_user).sort_by(&:date).reverse
     respond_to do |format|
       format.json { send_data JSON.pretty_generate(JSON.parse(entries.to_json(:only => [:date, :body, :image_url]))) }
     end
  end

  private
    def entry_params
      params.require(:entry).permit(:date, :entry, :image_url, :inspiration_id)
    end

    def require_permission
      if current_user != Entry.find(params[:id]).user
        flash[:alert] = "Not authorized"
        redirect_to entries_path
      end
    end

    def import_ohlife_entries(data)
      errors = []
      user = current_user #protect users from importing into someone else's entries

      split_at_date_regex = /[201]{3}[0-4]{1}-[0-1]{1}[0-9]{1}-[0-3]{1}[0-9]{1}/
      dates = data.scan(split_at_date_regex)
      bodies  = data.split(split_at_date_regex)
      bodies.shift

      dates.each_with_index do |date,i|
        #remove line breaks at begininng and end          
        body = ActionController::Base.helpers.simple_format(bodies[i])
        body.gsub!(/\A(\<p\>\<\/p\>)/,"")
        body.gsub!(/(\<p\>\<\/p\>)\z/,"")
        entry = user.entries.create(:date => date, :body => body, :inspiration_id => 1)
        unless entry.save
          errors << date
        end
      end

      flash[:notice] = "Finished importing " + ActionController::Base.helpers.pluralize(dates.count,"entry")
      if errors.present?
        flash[:alert] = "<strong>"+ActionController::Base.helpers.pluralize(errors.count,"error") + " while importing:</strong>"
        errors.each do |error|
          flash[:alert] << "<br>"+error
        end
      end
    end   
     
end
