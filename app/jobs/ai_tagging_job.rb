class AiTaggingJob < ActiveJob::Base
  queue_as :default

  def perform(entries)
    return nil if ::Rails.env.test?

    Entry::AiTagger.new.tag(entries)
  end
end
