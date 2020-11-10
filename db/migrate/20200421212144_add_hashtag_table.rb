class AddHashtagTable < ActiveRecord::Migration[4.2][6.0]
  def change
     create_table :hashtags do |t|
        t.references :user, index: true
        t.string :tag
        t.date :date, :null => true
        t.timestamps
      end
  end
end
