class AdminController < ApplicationController
  before_action :authenticate_user!, except: [:mailgun]
  before_action :authenticate_admin!, except: [:mailgun]
  skip_before_filter :verify_authenticity_token, only: [:mailgun]

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

  def mailgun
    if params['domain'] == ENV['MAIN_DOMAIN'] || params['domain'] == ENV['SMTP_DOMAIN']
      ActionMailer::Base.mail(from: "hello@#{ENV['MAIN_DOMAIN']}", to: "hello@#{ENV['MAIN_DOMAIN']}", subject: "[DABBLE.ME] #{params['event']}", body: "#{params['recipient']}\n\n-----------\n\n#{params['body-plain']}").deliver
    end
    render json: note, status: :ok
  end

  private

end
