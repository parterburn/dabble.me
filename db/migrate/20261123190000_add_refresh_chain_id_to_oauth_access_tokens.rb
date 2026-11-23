# Which sign-in a token descends from by refresh (OauthRefreshReuse): the id of the first token
# of its chain. Set when a refresh rotates a token (config/initializers/doorkeeper.rb). NULL on
# a token that started a chain (a fresh sign-in) and on tokens from before this column.
class AddRefreshChainIdToOauthAccessTokens < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :oauth_access_tokens, :refresh_chain_id, :bigint
    add_index :oauth_access_tokens, :refresh_chain_id, algorithm: :concurrently
  end
end
