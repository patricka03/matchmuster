class AddStripeAccountIdToTeams < ActiveRecord::Migration[8.1]
  def change
    add_column :teams, :stripe_account_id, :string
    add_index :teams, :stripe_account_id, unique: true
  end
end
