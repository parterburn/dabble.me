class WelcomeController < ApplicationController
  def index
    if current_user
      @last_entry = Entry.includes(:inspiration).where(:user_id => current_user).sort_by(&:date).last
    end
  end

  def redirect_vidcast
    redirect_to "https://vidcast.dabble.me#{request.fullpath.gsub('/cast','')}", status: :moved_permanently
  end
end
