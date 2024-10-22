class WelcomeController < ApplicationController
  def index
    @total_entries = Entry.count
    redirect_to latest_entry_path if user_signed_in?
  end
end
