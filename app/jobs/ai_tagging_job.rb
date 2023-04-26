class AiTaggingJob < ActiveJob::Base
  queue_as :default

  def perform(entries)
    Entry::AiTagger.new.tag(entries)
  end
end
