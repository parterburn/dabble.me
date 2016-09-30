Clarifai::Rails.setup do |config|

  config.client_id = ENV['CLARIFAI_CLIENT_ID']

  config.client_secret = ENV['CLARIFAI_CLIENT_SECRET']

end
