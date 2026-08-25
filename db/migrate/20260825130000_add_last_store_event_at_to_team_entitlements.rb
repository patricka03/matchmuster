class AddLastStoreEventAtToTeamEntitlements <
  ActiveRecord::Migration[8.1]

  def change
    add_column :team_entitlements,
               :last_store_event_at,
               :datetime
  end
end
