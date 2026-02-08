class WelcomeController < ApplicationController
  layout "marketing"

  def index
    redirect_to latest_entry_path if user_signed_in?

    @stats = Rails.cache.fetch("welcome_stats", expires_in: 1.day) do
      { total_entries: Entry.count, emails_sent: User.sum(:emails_sent), emails_received: User.sum(:emails_received) }
    end
  end

  def subscribe
    if user_signed_in? && current_user.is_pro?
      render "pro_subscribed", layout: 'application'
    else
      render "subscribe", layout: "marketing"
    end
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
end
