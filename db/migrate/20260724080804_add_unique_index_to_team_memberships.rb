class AddUniqueIndexToTeamMemberships < ActiveRecord::Migration[8.1]
  def change
    add_index :team_memberships, [:user_id, :team_id], unique: true
  end
end
