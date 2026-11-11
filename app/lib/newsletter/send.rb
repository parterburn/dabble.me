# frozen_string_literal: true

class Newsletter
  # Works out who gets which letter of a newsletter, and queues the emails.
  # Run through `rake newsletter:send`.
  class Send
    BATCH_SIZE = 500

    def initialize(newsletter)
      @newsletter = newsletter
    end

    # { variant name => [user ids] } for everyone not yet sent this newsletter.
    def plan
      @plan ||= begin
        plan = @newsletter.variants.to_h { |variant| [variant.name, []] }
        delivered = @newsletter.delivered_user_ids.to_set
        @newsletter.audience.in_batches(of: BATCH_SIZE) do |batch|
          ids = batch.pluck(:id).reject { |id| delivered.include?(id) }
          counts = @newsletter.entry_counts(ids)
          ids.each { |id| plan[@newsletter.variant_for(nil, entries_in_year: counts.fetch(id, 0))] << id }
        end
        plan
      end
    end

    def already_delivered
      @newsletter.delivered_user_ids.size
    end

    # Reasons this newsletter must not go out yet. Empty when it is ready.
    def blockers
      blockers = []
      @newsletter.variants.each do |variant|
        blockers << "#{variant.name}.md still has a TODO in it" if @newsletter.letter(variant.name).unfinished?
      end
      blockers << "MAILING_ADDRESS is not set; the footer needs a postal address" if ENV["MAILING_ADDRESS"].blank?
      blockers
    end

    # Queues one job per person, spaced so at most `per_minute` go out a minute.
    def deliver!(per_minute:)
      raise Newsletter::Error, blockers.join("; ") if blockers.any?

      gap = 60.0 / per_minute
      plan.values.flatten.each_with_index do |user_id, index|
        NewsletterDeliveryJob.set(wait: (index * gap).seconds).perform_later(user_id, @newsletter.key)
      end.size
    end
  end
end
