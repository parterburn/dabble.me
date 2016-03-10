MailgunWebhooks.api_key = ENV['MAILGUN_API_KEY']
MailgunWebhooks.api_host = ENV['MAIN_DOMAIN']

MailgunWebhooks.on(:bounced) do |data|
  if (user = User.find_by(email: data['recipient']))
    # If the address bounced, don't try sending anymore
    if user.is_free?
      user.frequency = []
      user.save
    end
  end
end

MailgunWebhooks.on(:complained) do |data|
  if (user = User.find_by(email: data['recipient']))
    # If the user complained unsubscribe them if free
    if user.is_free?
      user.frequency = []
      user.save
    end
    ActionMailer::Base.mail(from: "hello@#{ENV['MAIN_DOMAIN']}", to: "hello@#{ENV['MAIN_DOMAIN']}", subject: "[DABBLE.ME] #{params['event']}", body: "#{data['recipient']} (#{user.plan})\n\n-----------\n\n#{data['body-plain']}").deliver
  end
end