class EntriesController < ApplicationController
  before_action :authenticate_user!
  
  before_filter :require_permission, except: [:index, :new, :create, :import, :process_import]

  def index
    @entries = Entry.where(:user_id => current_user).sort_by(&:date).reverse
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
    @entry = @user.entries.create(entry_params)
   
    if @entry.save
      redirect_to @entry
    else
      render 'new'
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
      params.require(:entry).permit(:date, :body, :image_url)
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
        body = bodies[i].gsub(/[\r\n]+/, "<br><br>") if bodies[i].present?
        #clean up extra <br> at beginning and end
        body.gsub!(/\A(\<br\>)/,"")
        body.gsub!(/\A(\<br\>)/,"")
        body.gsub!(/(\<br\>)\z/,"")
        body.gsub!(/(\<br\>)\z/,"")
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
