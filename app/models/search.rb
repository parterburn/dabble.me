class Search
  include ActiveModel::Model

  attr_accessor :user, :term

  # Supports three query styles, shared by the search page and exports:
  #   foo OR bar   -> body contains any term (case-insensitive)
  #   "exact word" -> whole-word phrase match (case-insensitive)
  #   anything     -> body contains the substring (case-insensitive)
  # Matching runs in Ruby (Entry::Matcher), never in SQL, so user input is
  # always compared literally.
  def entries
    matcher = Entry::Matcher.parse(term)
    return user.entries.none if matcher.nil?

    matcher.filter(user.entries)
  end
end
