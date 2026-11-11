# frozen_string_literal: true

class Newsletter
  # Works out who gets which variant of a newsletter, and queues the emails.
  # Run through `rake newsletter:send`.
  class Send
    BATCH_SIZE = 500

    # plan limits the send to "pro" or "free". limit caps how many emails
    # one run queues, for building up a new sending domain a day at a time.
    def initialize(newsletter, plan: nil, limit: nil)
      @newsletter = newsletter
      @plans = plan ? [plan] : newsletter.plans
      @limit = limit
    end

    # { variant name => [user ids] } for everyone not yet sent this newsletter.
    def plan
      @plan ||= begin
        plan = @newsletter.variants.select { |variant| @plans.include?(variant.plan) }.to_h { |variant| [variant.name, []] }
        delivered = @newsletter.delivered_user_ids.to_set
        @plans.each do |audience_plan|
          @newsletter.audience(audience_plan).in_batches(of: BATCH_SIZE) do |batch|
            ids = batch.pluck(:id).reject { |id| delivered.include?(id) }
            counts = @newsletter.entry_counts(ids)
            ids.each { |id| plan[@newsletter.variant_name(audience_plan, counts.fetch(id, 0))] << id }
          end
        end
        plan
      end
    end

    # The people this run would email: everyone planned, up to the limit.
    def queue
      ids = plan.values.flatten
      @limit ? ids.first(@limit) : ids
    end

    def already_delivered
      @newsletter.delivered_user_ids.size
    end

    # Reasons this newsletter must not go out yet. Empty when it is ready.
    def blockers
      blockers = []
      blockers << "letter.md still has a TODO in it" if @newsletter.letter.unfinished?
      blockers << "MAILING_ADDRESS is not set; the footer needs a postal address" if ENV["MAILING_ADDRESS"].blank?
      blockers
    end

    # Queues one job per person, spaced so at most `per_minute` go out a minute.
    def deliver!(per_minute:)
      raise Newsletter::Error, blockers.join("; ") if blockers.any?

      gap = 60.0 / per_minute
      queue.each_with_index do |user_id, index|
        NewsletterDeliveryJob.set(wait: (index * gap).seconds).perform_later(user_id, @newsletter.key)
      end.size
    end
  end
end
