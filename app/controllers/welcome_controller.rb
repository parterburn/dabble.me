class WelcomeController < ApplicationController
  def index
    if current_user
      @last_entry = Entry.where(:user_id => current_user).sort_by(&:date).last
    end
  end
end
