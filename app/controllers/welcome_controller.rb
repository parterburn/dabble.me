class WelcomeController < ApplicationController
  layout "marketing"
  before_action :refuse_when_closing, only: [:subscribe]

  def index
    redirect_to today_path if user_signed_in? && params[:s] != "0"

    @stats = Rails.cache.fetch("welcome_stats", expires_in: 1.day) do
      { total_entries: Entry.count, emails_sent: User.sum(:emails_sent), emails_received: User.sum(:emails_received) }
    end
  end

  # What people see once a closing is announced (SiteClosure): the date, and
  # how to export. It replaces the site itself from that date on.
  def goodbye
    redirect_to root_path unless site_closure
  end

  def subscribe
    # A gifted year (Gift) is PRO without a subscription, so it gets the checkout buttons.
    if user_signed_in? && current_user.is_pro? && !current_user.gifted_pro?
      render "pro_subscribed", layout: 'application'
    else
      render "subscribe", layout: "marketing"
    end
  end

  def support
    # Support/FAQ page
  end

  def mcp_server
    # Plain-language AI Connector guide for journalers.
  end

  def mcp_server_developers
    tools = Mcp::DabbleServer::TOOLS.partition { |tool| tool != Mcp::Tools::GetImageUploadUrl }.flatten
    @mcp_tools = tools.map do |tool|
      schema = tool.input_schema.to_h
      {
        name: tool.tool_name,
        title: tool.title,
        description: tool.description,
        properties: schema[:properties] || {},
        required: schema[:required] || []
      }
    end
  end

  def day_one_ai_journaling
    # Comparison page for people choosing an MCP-enabled journal.
  end

  def day_one_alternative
    # SEO landing page for Day One users considering email journaling + import.
  end

  def best_journaling_apps_with_mcp
    # Guide to the journaling apps that connect to ChatGPT and Claude, in plain language.
  end

  def journal_app
    # The iOS app, with its screenshots.
  end

  def how_to_start_journaling
    # A beginner's guide to keeping a journal, with journal prompts.
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
