module EntryMutator
  def create!(author, attrs)
    entry = author.entries.new(attrs)
    entry.reviewer = rand(User.all)

    entry.save!
    entry
  end

  def merge!(existing_entry, attrs)
    existing_entry.body += "<hr>#{attrs[:entry]}"
    existing_entry.reviewer = rand(User.all)

    existing_entry.save!
    existing_entry
  end
end