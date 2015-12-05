class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin!

  def users
    if params[:entries] == 'all'
      @title = 'ADMIN ENTRIES for ALL USERS'
      if params[:user_id].present?
        user = User.find(params[:user_id])
        @entries = user.entries.includes(:inspiration)
        @title = "ADMIN ENTRIES for <a href='/admin/users?email=#{user.email}'>#{user.email}</a>" if user.present?
      else
        @entries = Entry.includes(:user, :inspiration).all
      end

      if params[:photos].present?
        @entries = Kaminari.paginate_array(@entries.only_images.order('id DESC')).page(params[:page]).per(params[:per])
        render 'photo_grid'
      else
        @entries = Kaminari.paginate_array(@entries.order('id DESC')).page(params[:page]).per(params[:per])
        render 'entries/index'
      end
    else
      if params[:email].present?
        users = User.includes(:payments).where("email LIKE '%#{params[:email]}%'")
      elsif params[:user_key].present?
        users = User.where("user_key LIKE '%#{params[:user_key]}%'")
      else
        users = User.includes(:payments, :entries).all
      end
      @user_list = users.order('id DESC').page(params[:page]).per(params[:per])
      render 'users'
    end
  end

  def stats
    @dashboard = AdminStats.new
  end

  private

end
