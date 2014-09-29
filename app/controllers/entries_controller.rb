class EntriesController < ApplicationController
  before_action :authenticate_user!
  
  before_filter :require_permission, except: [:index, :new, :create, :import, :process_import]

  def index
    begin
      if params[:year].present? && params[:month].present?
        @entries = Entry.where(:user_id => current_user).where("date >= to_date('#{params[:year]}-#{params[:month]}','YYYY-MM') AND date < to_date('#{params[:year]}-#{params[:month].to_i+1}','YYYY-MM')").sort_by(&:date).reverse
        date = Date.parse(params[:month]+'/'+params[:year])
        @title = "#{ActionController::Base.helpers.pluralize(@entries.count,'entry')} from #{date.strftime('%b %Y')}"      
      elsif params[:year].present?
        @entries = Entry.where(:user_id => current_user).where("date >= '#{params[:year]}-01-01'::DATE AND date <= '#{params[:year]}-12-31'::DATE").sort_by(&:date).reverse
        @title = "#{ActionController::Base.helpers.pluralize(@entries.count,'entry')} from #{params[:year]}"
      else
        ActionController::ShowAllEntries
      end
    rescue
      @entries = Entry.where(:user_id => current_user).sort_by(&:date).reverse
      @title = "All #{ActionController::Base.helpers.pluralize(@entries.count,'entry')}"      
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

  def new
    @entry = Entry.new
  end

  def create
    @user = current_user

    selected_date = Date.parse(params[:entry][:date])
    @existing_entry = Entry.where(:user_id => @user.id, :date => selected_date.beginning_of_day..selected_date.end_of_day).first
    
    if @existing_entry.present?
      #existing entry exists, so add to it
      @existing_entry.body += "<br><br>--------------------------------<br><br>#{params[:entry][:entry]}"
      @existing_entry.save
      redirect_to entry_path(@existing_entry)
    else
      @entry = @user.entries.create(entry_params)
      if @entry.save
        #save new entry & view it
        redirect_to @entry
      else
        #errors
        render 'new'
      end
    end
  end

  def edit
    @entry = Entry.find(params[:id])
  end

  def update
    @entry = Entry.find(params[:id])
   
    if @entry.update(entry_params)
      redirect_to @entry
    else
      render 'edit'
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

  private
    def entry_params
      params.require(:entry).permit(:date, :entry, :image_url)
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
