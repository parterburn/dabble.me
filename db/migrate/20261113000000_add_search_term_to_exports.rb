# The search an export was made from, so its file and its page can be named
# after it. Encrypted (Export encrypts :search_term), like the journal text.
class AddSearchTermToExports < ActiveRecord::Migration[8.1]
  def change
    add_column :exports, :search_term, :text
  end
end
