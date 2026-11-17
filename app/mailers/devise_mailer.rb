# Password reset and unlock come from support. Confirmation and the other
# Devise messages keep Devise.mailer_sender ("Paul // Dabble Me").
class DeviseMailer < Devise::Mailer
  def reset_password_instructions(record, token, opts = {})
    super(record, token, with_support_sender(opts))
  end

  def unlock_instructions(record, token, opts = {})
    super(record, token, with_support_sender(opts))
  end

  private

  def with_support_sender(opts)
    sender = "Dabble Me Support <hello@#{ENV['MAIN_DOMAIN']}>"
    { template_path: 'devise/mailer' }.merge(opts).merge(from: sender, reply_to: sender)
  end
end
