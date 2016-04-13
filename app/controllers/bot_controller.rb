class BotController < ApplicationController
  def webhook
    if params['hub.verify_token'] == ENV['FB_MESSENGER_VERIFY_TOKEN']
      render text: params['hub.challenge']
    else
      head :forbidden
    end
  end
end
