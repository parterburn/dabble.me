# Stores each entry's word count so stats can sum a number instead of running
# regular expressions over entry text in SQL. Entry sets it on save.
class AddWordCountToEntries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BATCH_SIZE = 10_000

  # Same rule as Entry.count_words: tags and HTML entities become spaces, then
  # whitespace-separated runs count.
  BACKFILL_SQL = <<~SQL.squish
    UPDATE entries
    SET word_count = CASE WHEN stripped.body = '' THEN 0
                          ELSE array_length(regexp_split_to_array(stripped.body, '\\s+'), 1) END
    FROM (
      SELECT id, regexp_replace(
        regexp_replace(regexp_replace(COALESCE(body, ''), '<[^>]*>', ' ', 'g'), '&[#a-zA-Z0-9]+;', ' ', 'g'),
        '^\\s+|\\s+$', '', 'g'
      ) AS body
      FROM entries
      WHERE id BETWEEN %<first>d AND %<last>d AND word_count IS NULL
    ) AS stripped
    WHERE entries.id = stripped.id
  SQL

  def up
    add_column :entries, :word_count, :integer unless column_exists?(:entries, :word_count)

    max_id = select_value("SELECT MAX(id) FROM entries").to_i
    1.step(max_id, BATCH_SIZE) do |first|
      execute(format(BACKFILL_SQL, first: first, last: first + BATCH_SIZE - 1))
    end
  end

  def down
    remove_column :entries, :word_count
  end
end
