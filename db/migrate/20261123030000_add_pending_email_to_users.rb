# An address a signed-in account asked to move to, held until a code emailed there proves the
# inbox (EmailChangesController). users.email changes only then.
class AddPendingEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pending_email, :string
  end
end
