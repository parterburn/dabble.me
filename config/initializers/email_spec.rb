ActiveSupport.on_load(:action_mailer) do
  # fix https://github.com/email-spec/email-spec/issues/220
  module EmailSpec
    module Helpers; end
  end

  # fix warning "Neither Pony nor ActionMailer appear to be loaded so email-spec is requiring ActionMailer."
  require 'email_spec'
end
