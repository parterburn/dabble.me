class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin!

  def users
    # Это всё про @user_list вынести в отдельный ServiceObject или заюзать https://github.com/nebulab/simple_command
    # @user_list = Admin::Users.call(params) что типа этого тут надо

    if params[:email].present?
      users = User.where("email LIKE '%#{params[:email].downcase}%'")
    elsif params[:user_key].present?
      users = User.where("user_key LIKE '%#{params[:user_key]}%'")
    else
      users = User.all
    end
    @user_list = users.order('id DESC').page(params[:page]).per(params[:per])

    render 'users' # это лишнее
  end

  def photos
    @entries = Kaminari.paginate_array(Entry.only_images.order('id DESC')).page(params[:page]).per(params[:per])
  end

  def stats
    @dashboard = AdminStats.new
  end
end
