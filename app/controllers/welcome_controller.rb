class WelcomeController < ApplicationController
  def index
    redirect_to latest_entry_path if user_signed_in?
  end

  # неплохо б всё-таки объявить 'пустые' метода

  # def faqs; end
end
