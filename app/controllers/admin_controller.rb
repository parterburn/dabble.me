class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin!

  def users
    if params[:email].present?
      users = User.where("email ILIKE ?", "%#{params[:email].downcase}%")
    elsif params[:user_key].present?
      users = User.where("user_key ILIKE ?", "%#{params[:user_key]}%")
    else
      users = User.all
    end
    @user_list = users.order('id DESC').page(params[:page]).per(per_page)
    render 'users'
  end

  def photos
    @entries = Kaminari.paginate_array(Entry.select(:image, :user_id, :date).includes(:user).only_images.order('date DESC')).page(params[:page]).per(per_page)
  end

  def stats
    @dashboard = AdminStats.new
  end

  private

  def per_page
    params[:per].presence || 50
  end
end
