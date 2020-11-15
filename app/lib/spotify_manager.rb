module SpotifyManager
  def find_songs(body)
    songs = []
    if body.present?
      matches = body.scan(/open\.spotify\.com\/track\/(\w+)/)
      matches.uniq.each do |match|
        if (spotify_name = get_spotify_info_from_track_id(match.first)).present?
          songs << { spotify_id: match.first, artists: spotify_name.first, title: spotify_name.last }
        end
      end
    end
    songs
  end

  def get_spotify_info_from_track_id(track_id)
    grant = Base64.strict_encode64("#{ENV['SPOTIFY_API_CLIENT']}:#{ENV['SPOTIFY_API_SECRET']}")
    resp = RestClient.post("https://accounts.spotify.com/api/token", { grant_type: "client_credentials" }, { "Authorization": "Basic #{grant}" })
    oath_token = JSON.parse(resp.body)["access_token"]
    resp_song = RestClient.get("https://api.spotify.com/v1/tracks/#{track_id}", { "Authorization": "Bearer #{oath_token}" })
    song_data = JSON.parse(resp_song.body)
    unless song_data['error'].present?
      [song_data['artists'].map { |a| a['name'] }, song_data['name']]
    else
      nil
    end
  end
end