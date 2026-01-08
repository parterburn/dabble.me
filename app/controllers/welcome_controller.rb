class WelcomeController < ApplicationController
  layout :choose_layout

  def index
    redirect_to latest_entry_path if user_signed_in?
    @total_entries = Entry.count
  end

  def support
    # Support/FAQ page
  end

  def privacy
    # Privacy policy page
  end

  def terms
    # Terms of service page
  end

  def ohlife_alternative
    # SEO landing page for OhLife users
  end

  private

  def choose_layout
    if user_signed_in?
      'application'
    else
      'marketing'
    end
  end
end
