# frozen_string_literal: true

# One-off: strip stored DabbleMeGPT conversations out of entry bodies, leaving
# the writer's own entry. Reflections aren't stored any more (see
# Entry::AiAssistant), so these are leftovers from the retired conversation
# feature.
#
# Production console:
#   load Rails.root.join('script/cleanup_ai_conversations.rb')
#   AiConversationCleanup.report                      # who has AI entries, and how many (read-only)
#   AiConversationCleanup.preview(user_id)            # before/after for one user's entries (read-only)
#   AiConversationCleanup.apply!(user_ids: [1, 2])    # rewrite those users' entries
#   AiConversationCleanup.apply!(user_ids: :all)      # rewrite everyone's
#   AiConversationCleanup.restore!(path)              # put bodies back from the backup apply! wrote
#
# How a body is cleaned: it's split on <hr> into the pieces that were glued
# together over time. Each piece is one of:
#   - an AI reply                                       -> dropped
#     (the dabblemegpt div, or the "🤖 DabbleMeGPT:" label; saving through the
#     web editor renames that label to "🤖 AI Assistant:")
#   - a "👤 You:" piece after an AI reply (your reply)   -> dropped (or kept with keep_replies: true)
#   - a "👤 You:" piece before any AI reply              -> kept, label removed. That's an email you
#                                                           sent to ai.dabble.me for a day that already
#                                                           had an entry, so it's journal text, not a reply.
#   - anything else (the entry, later emails or edits)  -> kept
# Entries that would end up empty are skipped and listed.
#
# apply! uses update_columns, so no callbacks run (no Spotify lookups), and it
# bumps updated_at so cached entry fragments refresh. It writes every original
# body to a JSON backup first. On Railway that file lives in the container and
# disappears on the next deploy or restart, so take a database backup too.

module AiConversationCleanup
  # Markers the app wrote for AI replies. A bare "DabbleMeGPT" isn't enough:
  # someone could have typed it.
  AI_PIECE = /data-content=["']?dabblemegpt|🤖\s*(?:<\/?\w+[^>]*>\s*)*(?:DabbleMeGPT|AI Assistant)\s*:/i
  SQL_MATCH = "body ILIKE '%data-content=_dabblemegpt%' OR body LIKE '%🤖 DabbleMeGPT:%' OR body LIKE '%🤖 AI Assistant:%'"
  HR = %r{<hr\b[^>]*/?>}i
  YOU_LABEL = %r{\A\s*(?:<p>\s*)?<(strong|b)>\s*👤\s*You:\s*</\1>\s*(?:<br\s*/?>)?}i

  module_function

  def scope
    Entry.unscoped.where(SQL_MATCH)
  end

  def report
    counts = scope.group(:user_id).count
    if counts.empty?
      puts "No entries with stored AI conversations."
      return {}
    end

    users = User.where(id: counts.keys).index_by(&:id)
    puts "\n#{'=' * 72}"
    puts "Entries with stored AI conversations: #{counts.values.sum} across #{counts.size} users"
    puts "=" * 72
    puts format("%-8s %-36s %-20s %-6s %s", "user_id", "email", "plan", "opt-in", "entries")
    counts.sort_by { |_id, n| -n }.each do |user_id, n|
      user = users[user_id]
      puts format("%-8s %-36s %-20s %-6s %d", user_id, user&.email.to_s.truncate(36), user&.plan.to_s.truncate(20), user&.ai_opt_in? ? "yes" : "no", n)
    end

    robot_only = Entry.unscoped.where("body LIKE ?", "%🤖%").where.not(id: scope.select(:id)).count
    puts "\n#{robot_only} other entries contain 🤖 but no AI reply marker (the writer's own emoji). Left alone." if robot_only.positive?
    counts
  end

  def preview(user_id, limit: 10, keep_replies: false)
    entries = scope.where(user_id: user_id).order(:date)
    puts "User #{user_id}: #{entries.count} entries (showing up to #{limit})"
    entries.limit(limit).each do |entry|
      cleaned = clean(entry.body, keep_replies: keep_replies)
      puts "\n#{'-' * 72}"
      puts "Entry #{entry.id} (#{entry.date.to_date})  #{entry.body.length} -> #{cleaned.to_s.length} chars#{'  [SKIP: would be empty]' if cleaned.blank?}"
      puts "BEFORE: #{plain(entry.body).truncate(400)}"
      puts "AFTER:  #{plain(cleaned).truncate(400)}"
    end
    nil
  end

  def apply!(user_ids:, keep_replies: false)
    raise ArgumentError, "pass user_ids: [ids] or user_ids: :all" if user_ids.blank?

    entries = user_ids == :all ? scope : scope.where(user_id: Array(user_ids))
    backup = Rails.root.join("tmp", "ai_cleanup_backup_#{Time.current.strftime('%Y%m%d%H%M%S')}.json")
    FileUtils.mkdir_p(backup.dirname)
    File.write(backup, entries.pluck(:id, :body).to_h.to_json)
    puts "Backed up #{entries.count} bodies to #{backup}"

    changed = 0
    skipped = []
    entries.find_each do |entry|
      cleaned = clean(entry.body, keep_replies: keep_replies)
      if cleaned.blank?
        skipped << entry.id
      elsif cleaned != entry.body
        entry.update_columns(body: cleaned, updated_at: Time.current)
        changed += 1
      end
    end

    puts "Cleaned #{changed} entries."
    puts "Skipped #{skipped.size} that would be empty: #{skipped.join(', ')}" if skipped.any?
    puts "Remaining entries with AI markers: #{scope.count}"
    backup.to_s
  end

  def restore!(path)
    bodies = JSON.parse(File.read(path))
    Entry.unscoped.where(id: bodies.keys).find_each do |entry|
      entry.update_columns(body: bodies[entry.id.to_s], updated_at: Time.current)
    end
    puts "Restored #{bodies.size} entries from #{path}"
  end

  def clean(body, keep_replies: false)
    seen_ai = false
    kept = body.to_s.split(HR).filter_map do |piece|
      if piece.match?(AI_PIECE)
        seen_ai = true
        nil
      elsif you_piece?(piece)
        next if seen_ai && !keep_replies

        piece.match?(YOU_LABEL) ? piece.sub(YOU_LABEL, "") : piece.sub("👤 You:", "")
      else
        piece
      end
    end
    kept.map(&:strip).reject { |piece| plain(piece).blank? && !piece.match?(/<(img|iframe)\b/i) }.join("<hr>")
  end

  def you_piece?(piece)
    plain(piece).start_with?("👤 You:")
  end

  def plain(html)
    ActionController::Base.helpers.strip_tags(html.to_s).squish
  end
end
