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
    # `uploading_image_at` is required by Entry#uploading_image? (called through
    # image_code → display_image_url in the view). Keep `:id` for AR identity
    # and any future per-entry actions. Heavy columns like body/original_email
    # stay excluded so the 300-per-page grid stays cheap.
    entries = Entry.select(:id, :image, :user_id, :date, :uploading_image_at)
                   .includes(:user)
                   .only_images
                   .order('date DESC')
    @entries = Kaminari.paginate_array(entries).page(params[:page]).per(per_page)
  end

  def stats
    @dashboard = AdminStats.new
  end

  private

  def per_page
    params[:per].presence || 300
  end
end
