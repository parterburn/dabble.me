class EntriesController < ApplicationController
  before_action :authenticate_user!
  
  before_filter :require_permission, except: [:index, :new, :create]

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
end
