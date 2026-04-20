require 'rails_helper'

RSpec.describe 'MCP security routes', type: :request do
  let(:user) do
    create(:user, plan: 'PRO Monthly PayHere').tap do |record|
      record.generate_otp_secret
      record.update!(otp_enabled: true, otp_enabled_on: Time.current)
    end
  end

  before do
    sign_in user
  end

  it 'posts to the MCP token generation route successfully' do
    post generate_mcp_token_path, params: { user: { current_password: user.password } }

    expect(response).to redirect_to(security_path)
    expect(flash[:mcp_token]).to start_with('dmcp_')
    expect(user.reload.mcp_enabled).to eq(true)
  end
end
