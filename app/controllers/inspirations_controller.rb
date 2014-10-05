class InspirationsController < ApplicationController
  before_action :authenticate_user!
  before_filter :require_permission

  def index
    @inspirations = Inspiration.all.order(:category, :id)
    @last_updated = Inspiration.all.order(:updated_at).last
  end

  def new
    @inspiration = Inspiration.new
    @inspiration.category = "Question"
  end

  def create
    @inspiration = Inspiration.create(entry_params)
    if @inspiration.save
      flash[:notice] = "Inspiration created successfully!"
      @highlight = @inspiration.id
      redirect_to inspirations_path
    else
      render 'new'
    end
  end

  def edit
    @inspiration = Inspiration.find(params[:id])
  end

  def update
    @inspiration = Inspiration.find(params[:id])
    changed = @inspiration.was_changed?(params) ? true : false
    if @inspiration.update(entry_params)
      flash[:notice] = "Inspiration successfully updated!" if changed
      redirect_to inspirations_path
    else
      render 'edit'
    end
  end

  def show
    @inspiration = Inspiration.find(params[:id])
  end

  def destroy
    @inspiration = Inspiration.find(params[:id])
    @inspiration.destroy
    flash[:notice] = "Inspiration deleted successfully."
    redirect_to inspirations_path
  end

  private
    def entry_params
      params.require(:inspiration).permit(:category, :body)
    end

    def require_permission
      unless current_user.is_admin?
        flash[:alert] = "Not authorized"
        redirect_to entries_path
      end
    end
end
