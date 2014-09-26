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
    split_at_date_regex = /[201]{3}[0-4]{1}-[0-1]{1}[0-9]{1}-[0-3]{1}[0-9]{1}/
    dates = params[:entry][:text].scan(split_at_date_regex)
    bodies  = params[:entry][:text].split(split_at_date_regex)
    bodies.shift

    p "*"*100
    p bodies
    p "*"*100

    p "*"*100
    p dates
    p "*"*100

    import_ohlife_entries(bodies, dates)
    how_many = ActionController::Base.helpers.pluralize(bodies.count,"entry")
    flash[:notice] = "Done importing #{how_many}!"
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

    def import_ohlife_entries(bodies, dates)
      @user = current_user
      dates.each_with_index do |date,i|
        body = ""
        body = bodies[i].gsub(/[\r\n]+/, "<br><br>") if bodies[i].present?
        @entry = @user.entries.create(:date => date, :body => body, :inspiration_id => 1)
        @entry.save
      end
    end      
end
