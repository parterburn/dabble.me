class WelcomeController < ApplicationController
  def index
    return unless user_signed_in?
    @last_entry = current_user.entries.includes(:inspiration).sort_by(&:date).last
  end
end
