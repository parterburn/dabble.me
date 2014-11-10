Griddler.configure do |config|
  config.processor_class = EmailProcessor # CommentViaEmail
  config.processor_method = :process # :create_comment (A method on CommentViaEmail)
  config.reply_delimiter = "Dabble Me wrote\:|Just reply to this email with your entry|201[0-9]{1}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} GMT[\-\+][0-9]{2}:[0-9]{2} Dabble Me \<u[a-zA-Z0-9]{18}@post.dabble.me\>:"
  config.email_service = :sendgrid # :cloudmailin, :postmark, :mandrill, :mailgun
end