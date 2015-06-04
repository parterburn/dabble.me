class RenameDonationsTable < ActiveRecord::Migration
  def self.up
    rename_table :donations, :payments
  end

 def self.down
    rename_table :payments, :donations
 end
end
