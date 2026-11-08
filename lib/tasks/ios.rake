# frozen_string_literal: true

# Demo data for App Store screenshots of the iOS app (development only).
#
#   bundle exec rails ios:demo_account
#
# Creates (or resets) demo@dabble.ex / dabble-demo as a PRO account with a year of made-up
# entries, a few photos (Unsplash-licensed, via picsum.photos), and "On This Day" entries
# for today's date. Prints an access token for the iOS app's -DabbleDebugAccessToken
# launch argument so screenshot automation can skip the web sign-in sheet.
namespace :ios do
  desc "Create a demo PRO account with sample entries for iOS screenshots (development only)"
  task demo_account: :environment do
    abort "ios:demo_account only runs in development" unless Rails.env.development?

    user = User.find_or_initialize_by(email: "demo@dabble.ex")
    user.assign_attributes(password: "dabble-demo", first_name: "Alex", last_name: "Rivera",
                           plan: "PRO Monthly", send_timezone: "Mountain Time (US & Canada)",
                           send_time: "20:00", frequency: %w[Sun])
    user.save!
    user.entries.destroy_all

    today = Time.current.in_time_zone(user.send_timezone).to_date
    photo = ->(id) { "https://picsum.photos/id/#{id}/1600/1200" }

    entries = [
      [today - 1, <<~HTML, 1043],
        <p>Finally made it to <strong>Yosemite</strong>. We started the Mist Trail before sunrise and had Vernal Fall almost to ourselves.</p>
        <p>Things I want to remember:</p>
        <ul><li>The rainbow in the spray halfway up</li><li>Sam singing badly the entire descent</li><li>Cold sandwiches have never tasted better</li></ul>
        <p>Legs are wrecked. Heart is full. #hiking #travel</p>
      HTML
      [today - 2, <<~HTML, 1060],
        <p>Slow Saturday. Made pour-over with the beans from the farmers market and read on the porch until noon.</p>
        <p>I keep noticing how much better I feel on the days I don't check my phone first thing. <em>Note to self: keep the phone in the kitchen.</em></p>
      HTML
      [today - 4, <<~HTML, nil],
        <p>Big presentation went well. I was nervous all morning, but once I started talking it felt like a conversation instead of a performance.</p>
        <p>Maya pulled me aside afterwards and said it was the clearest version of the plan she's heard. Taking that one with me. #work #gratitude</p>
      HTML
      [today - 5, <<~HTML, 1062],
        <p>Biscuit has discovered the heated blanket and will not be leaving it until spring. #Biscuit</p>
      HTML
      [today - 7, <<~HTML, nil],
        <p>Ran 5 miles without stopping for the first time since the injury. Slow, but steady.</p>
        <p>Three things I'm grateful for today:</p>
        <ol><li>A body that keeps healing</li><li>The crisp fall air</li><li>Dad calling just to say hi</li></ol>
      HTML
      [today - 9, <<~HTML, 225],
        <p>Rainy day. Tea, soup, and the last hundred pages of <em>The Overstory</em>. Some books make you want to go stand next to a tree for a while. #reading</p>
      HTML
      [today - 12, <<~HTML, nil],
        <p>Hard conversation with Jordan tonight. We didn't fix everything, but we listened to each other, which felt like the real win.</p>
      HTML
      [today - 15, <<~HTML, 429],
        <p>Last farmers market of the season. Bought far too many raspberries and zero regrets. Made jam with Sam after dinner. #cooking</p>
      HTML
      [today - 19, <<~HTML, nil],
        <p>Started a pottery class! My first bowl looks more like an ashtray, but the instructor says that's how everyone starts. #newthings</p>
      HTML
      [today - 24, <<~HTML, 1039],
        <p>Day trip to the falls. The trail was muddy and the waterfall was <strong>roaring</strong> after all the rain. #hiking</p>
      HTML
      [today - 31, <<~HTML, nil],
        <p>Halloween. Forty-two trick-or-treaters, which is a neighborhood record. The dinosaur costume on the little one next door was the clear winner.</p>
      HTML
      [today - 38, <<~HTML, nil],
        <p>Quiet week. Mostly work and early nights. Sometimes the boring weeks are the ones that refill the tank.</p>
      HTML
      [today - 52, <<~HTML, 1015],
        <p>Norway, day 3. Hiked up to Preikestolen and sat at the edge for an hour. I don't think a photo can hold a view like that. #travel</p>
      HTML
      [today - 75, <<~HTML, nil],
        <p>Summer is winding down. Grateful for long evenings on the porch and for friends who show up with tomatoes from their garden.</p>
      HTML
      [today - 120, <<~HTML, nil],
        <p>One year at the new job. I was so scared to make the leap, and it's turned out to be one of the best decisions I've made. #work</p>
      HTML
      [today - 1.year, <<~HTML, 164],
        <p>Bruges! Wandered the canals all afternoon and ate an unreasonable number of waffles. Sam says I'm "a waffle person now." I've accepted it. #travel</p>
      HTML
      [today - 2.years, <<~HTML, nil],
        <p>First snow of the year. Built a lopsided snowman and drank cocoa by the window. Some days are just simple and good.</p>
      HTML
      [today - 3.years, <<~HTML, nil],
        <p>Moved into the new apartment today. Boxes everywhere, no curtains yet, pizza on the floor. It already feels like home.</p>
      HTML
    ]

    entries.each do |date, body, photo_id|
      entry = user.entries.create!(date: date.to_s, body: body.strip)
      next unless photo_id

      begin
        entry.remote_image_url = photo.call(photo_id)
        entry.save!
      rescue StandardError => e
        # Usually missing/expired AWS credentials in .env; the entry is still useful without its photo.
        warn "Skipped photo for #{date}: #{e.class}: #{e.message.lines.first&.strip}"
        entry.reload
      end
    end

    # A dated hashtag (like a pet's or kid's birthday): the app shows how old Biscuit was on each entry.
    user.original_hashtags.destroy_all
    user.original_hashtags.create!(tag: "Biscuit", date: today - 3.years - 5.months)

    app = MobileApp.ensure_application!
    Doorkeeper::AccessToken.where(resource_owner_id: user.id, application_id: app.id).update_all(revoked_at: Time.current)
    token = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: user.id, scopes: MobileApp::SCOPE, expires_in: 1.day)

    puts "Demo account: demo@dabble.ex / dabble-demo (#{user.entries.count} entries, #{user.entries.only_images.count} with photos)"
    puts "Access token (1 day): #{token.plaintext_token}"
  end

  desc "PRO account with no entries or hashtags (UI test for first-time hashtag suggestions); prints a token"
  task empty_account: :environment do
    abort "ios:empty_account only runs in development" unless Rails.env.development?

    user = User.find_or_initialize_by(email: "empty-demo@dabble.ex")
    user.password = "dabble-empty-demo" if user.new_record?
    user.plan = "PRO Monthly"
    user.save!
    user.entries.destroy_all
    user.original_hashtags.destroy_all

    app = MobileApp.ensure_application!
    token = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: user.id, scopes: MobileApp::SCOPE, expires_in: 1.day)
    puts "Empty account: empty-demo@dabble.ex"
    puts "Access token (1 day): #{token.plaintext_token}"
  end

  desc "Free account (UI tests for PRO-only controls); prints a token"
  task free_account: :environment do
    abort "ios:free_account only runs in development" unless Rails.env.development?

    user = User.find_or_initialize_by(email: "free-demo@dabble.ex")
    user.password = "dabble-free-demo" if user.new_record?
    user.assign_attributes(plan: "Free", send_timezone: "Mountain Time (US & Canada)", send_time: "20:00", frequency: %w[Sun])
    user.save!

    app = MobileApp.ensure_application!
    token = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: user.id, scopes: MobileApp::SCOPE, expires_in: 1.day)
    puts "Free account: free-demo@dabble.ex"
    puts "Access token (1 day): #{token.plaintext_token}"
  end
end
