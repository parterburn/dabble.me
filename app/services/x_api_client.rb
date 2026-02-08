# X (Twitter) API v2 client. Pass a User with X connected, or a raw access_token.
# When initialized with a user, auto-refreshes the token before each request.
class XApiClient
  BASE_URL = 'https://api.x.com'
  BOOKMARKS_MAX_RESULTS = 10

  def initialize(user: nil, access_token: nil)
    @user = user
    @access_token = access_token
  end

  # Fetches bookmarks for the authenticated user.
  # Uses user.x_uid if available, otherwise resolves via /2/users/me.
  def bookmarks(max_results: BOOKMARKS_MAX_RESULTS, pagination_token: nil)
    uid = @user&.x_uid || fetch_my_uid
    return error_response('Could not resolve user ID') unless uid

    params = {
      'max_results' => [[max_results, 1].max, 100].min,
      'tweet.fields' => 'id,text,created_at,author_id,public_metrics,entities',
      'expansions' => 'author_id',
      'user.fields' => 'id,name,username,profile_image_url'
    }
    params['pagination_token'] = pagination_token if pagination_token.present?

    resp = connection.get("/2/users/#{uid}/bookmarks", params)
    resp.success? ? resp.body : error_response(resp.body.dig('detail') || "HTTP #{resp.status}")
  end

  # Returns the authenticated user's profile.
  def current_user
    resp = connection.get('/2/users/me', 'user.fields' => 'id,name,username,profile_image_url')
    resp.success? ? resp.body : nil
  end

  private

  def fetch_my_uid
    current_user&.dig('data', 'id')
  end

  def resolved_access_token
    if @user
      @user.fresh_x_access_token!
    else
      @access_token
    end
  end

  def error_response(message)
    { 'data' => nil, 'errors' => [{ 'message' => message }], 'meta' => { 'result_count' => 0 } }
  end

  def connection
    token = resolved_access_token
    Faraday.new(BASE_URL) do |f|
      f.request :json
      f.response :json
      f.request :authorization, 'Bearer', token
      f.options.timeout = 15
      f.options.open_timeout = 5
    end
  end
end
