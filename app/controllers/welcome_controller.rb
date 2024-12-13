class WelcomeController < ApplicationController
  def index
    redirect_to latest_entry_path if user_signed_in?
    @total_entries = Entry.count
  end
end
