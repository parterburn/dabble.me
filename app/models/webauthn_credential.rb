class WebauthnCredential < ActiveRecord::Base
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :nickname, presence: true
  validates :sign_count, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # An admin's passkeys go only from the Rails console (AdminAccounts.allow_passkey_removal).
  # `delete` and `delete_all` skip this, so nothing in the app may use them on an admin's.
  before_destroy :keep_admin_passkey

  private

  def keep_admin_passkey
    return unless AdminAccounts.protected?(user)
    return if AdminAccounts.passkey_removal_allowed?

    errors.add(:base, "Admin passkeys can only be removed from the Rails console.")
    throw :abort
  end
end
