class UserJob < ActiveJob::Base
  queue_as :default

  def perform(email_for_lookup, user_id)
    user = User.find(user_id)
    email_for_lookup ||= user.email
    if ENV['MAILCHIMP_API_KEY'].present? && Rails.env.production?
      begin
        gb = Gibbon::Request.new(api_key: ENV['MAILCHIMP_API_KEY'])
        gb.timeout = 10
        gb.lists(ENV['MAILCHIMP_LIST_ID']).members(Digest::MD5.hexdigest(email_for_lookup)).upsert(body: {email_address: user.email, status: "subscribed", merge_fields: {USER_ID: user.id, FNAME: user.first_name, LNAME: user.last_name, GROUP: "Signed Up"}})
      rescue
        # already subscribed or issues with Mailchimp's API
      end
    end
  end

end
