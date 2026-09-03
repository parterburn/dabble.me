# frozen_string_literal: true

namespace :business_metrics do
  desc "Snapshot founder metrics for today (or DATE=YYYY-MM-DD). Idempotent."
  task capture: :environment do
    date = ENV["DATE"].present? ? Date.parse(ENV["DATE"]) : Date.current
    snapshot = BusinessMetrics::Capture.call(on: date)
    puts "Captured business metrics for #{snapshot.captured_on}: MRR #{snapshot.mrr_cents} cents, ARR #{snapshot.arr_cents} cents"
  end

  desc "Send the weekly founder digest using live stats plus snapshots"
  task weekly_digest: :environment do
    BusinessMetrics::WeeklyDigest.call
    puts "Sent weekly founder digest"
  end
end
