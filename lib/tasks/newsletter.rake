# Sending the letters under newsletters/. See newsletters/README.md.
namespace :newsletter do
  desc "Email every variant of a newsletter to one account as a preview: rake 'newsletter:preview[2026-rewind,you@example.com]'"
  task :preview, %i[key email] => :environment do |_task, args|
    newsletter = Newsletter.find(args[:key])
    user = User.find_by(email: args[:email].to_s.downcase)
    abort "No account with the email #{args[:email].inspect}." unless user

    newsletter.variants.each do |variant|
      NewsletterMailer.letter(user, newsletter.key, variant.name, preview: true).deliver_now
      puts "Sent the #{variant.name} variant to #{user.email}."
    end
  end

  desc "Show who would get a newsletter; add SEND=yes to send it: rake 'newsletter:send[2026-rewind]'"
  task :send, [:key] => :environment do |_task, args|
    newsletter = Newsletter.find(args[:key])
    send = Newsletter::Send.new(newsletter)

    count = ->(number) { "#{number} #{number == 1 ? 'person' : 'people'}" }
    send.plan.each { |variant, user_ids| puts "#{variant}: #{count.call(user_ids.size)}" }
    puts "Already sent: #{count.call(send.already_delivered)}"
    send.blockers.each { |blocker| puts "Not ready: #{blocker}" }

    if ENV["SEND"] != "yes"
      puts "Nothing was sent. Run again with SEND=yes to send."
      next
    end
    abort "Not sent." if send.blockers.any?

    per_minute = ENV.fetch("PER_MINUTE", 120).to_i
    queued = send.deliver!(per_minute: per_minute)
    puts "Queued #{queued} emails at #{per_minute} a minute."
  end
end
