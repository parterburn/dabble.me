class UserJob < ActiveJob::Base
  queue_as :default
 
  def perform(user_id)
    user = User.find(user_id)
    if ENV['MAILCHIMP_API_KEY'].present?
      begin
        gb = Gibbon::Request.new(api_key: ENV['MAILCHIMP_API_KEY'])
        gb.timeout = 10
        gb.lists(ENV['MAILCHIMP_LIST_ID']).members(Digest::MD5.hexdigest(user.email.downcase)).upsert(body: {email_address: user.email, status: "subscribed", merge_fields: {FNAME: user.first_name, LNAME: user.last_name, GROUP: "Signed Up"}})
      rescue
        # already subscribed or issues with Mailchimp's API
      end
    end
  end

end
