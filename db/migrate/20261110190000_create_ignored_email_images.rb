class CreateIgnoredEmailImages < ActiveRecord::Migration[8.1]
  # The per-user signature rules that used to be hard-coded in EmailProcessor.
  # User 20829's rule skipped every application/octet-stream attachment; it
  # isn't carried over. Add a "looks like" rule for their signature instead.
  LEGACY_RULES = [
    [293, "filename", "cropped-img-0719-300x86.jpeg"],
    [10836, "filename", "b_logo.png"],
    [2541, "filename", "image001.jpg"]
  ].freeze

  def up
    create_table :ignored_email_images do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      # filename rules
      t.string :pattern
      # image rules: the sample the admin pointed at, and its ImageFingerprint
      t.string :image_url
      t.binary :fingerprint
      t.float :aspect_ratio
      t.timestamps
    end

    LEGACY_RULES.each do |user_id, kind, pattern|
      execute <<~SQL.squish
        INSERT INTO ignored_email_images (user_id, kind, pattern, created_at, updated_at)
        SELECT id, #{quote(kind)}, #{quote(pattern)}, NOW(), NOW() FROM users WHERE id = #{Integer(user_id)}
      SQL
    end
  end

  def down
    drop_table :ignored_email_images
  end
end
