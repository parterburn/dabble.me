class AddUsersToEntries < ActiveRecord::Migration
  def change

   create_table :products do |t|
      t.datetime :date, :null => false, :default => Time.now
      t.text :body
      t.text :image_url
      t.text :original_email_body
      t.integer :inspiration_id
      t.references :user, index: true
      t.timestamps
    end


  end
end
