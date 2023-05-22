class AiTaggingJob < ActiveJob::Base
  queue_as :default

  def perform(entry_ids)
    return nil if ::Rails.env.test?

    Entry::AiTagger.new.tag(entry_ids)
  end
end
