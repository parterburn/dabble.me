# Helpers for specs about encrypted columns.
module EncryptionHelpers
  # The value stored in the database, without decryption.
  def stored_value(record, column)
    record.class.connection.select_value(
      "SELECT #{column}::text FROM #{record.class.table_name} WHERE id = #{record.id}"
    )
  end

  # Writes a value straight into the column, as a row from before encryption.
  def store_plaintext(record, column, value)
    connection = record.class.connection
    connection.execute(
      "UPDATE #{record.class.table_name} SET #{column} = #{connection.quote(value)} WHERE id = #{record.id}"
    )
  end

  def ciphertext?(text)
    payload = JSON.parse(text.to_s)
    payload.is_a?(Hash) && payload.key?("p") && payload.key?("h")
  rescue JSON::ParserError
    false
  end

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end

RSpec.configure { |config| config.include EncryptionHelpers }
