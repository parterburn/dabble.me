require 'rails_helper'

RSpec.describe DeleteUserJob, type: :job do
  include_context 'has all objects'

  it 'does not delete the user when deletion was cancelled' do
    expect do
      described_class.perform_now(user.id)
    end.not_to change(User, :count)

    expect(user.reload).to be_persisted
  end

  it 'deletes the user when deletion is still pending' do
    user.update_column(:deleted_at, Time.current)

    expect do
      described_class.perform_now(user.id)
    end.to change(User, :count).by(-1)
  end
end
