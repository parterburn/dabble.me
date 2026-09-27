class Search
  include ActiveModel::Model

  attr_accessor :user, :term

  # Supports three query styles, shared by the search page and exports:
  #   foo OR bar   -> body contains any term (case-insensitive)
  #   "exact word" -> whole-word phrase match (case-insensitive)
  #   anything     -> body contains the substring (case-insensitive)
  # User input is escaped so LIKE wildcards and regex metacharacters match literally.
  def entries
    return user.entries.none if term.blank?

    if term.include?(' OR ')
      terms = term.split(' OR ').map(&:strip).reject(&:blank?)
      return user.entries.none if terms.empty?

      condition = terms.map { 'LOWER(entries.body) LIKE ?' }.join(' OR ')
      user.entries.where(condition, *terms.map { |t| like_pattern(t) })
    elsif term.include?('"')
      phrase = term.delete('"').strip
      return user.entries.none if phrase.blank?

      user.entries.where('entries.body ~* ?', "\\m#{Regexp.escape(phrase)}\\M")
    else
      user.entries.where('LOWER(entries.body) LIKE ?', like_pattern(term))
    end
  end

  private

  def like_pattern(value)
    "%#{ActiveRecord::Base.sanitize_sql_like(value.downcase)}%"
  end
end
