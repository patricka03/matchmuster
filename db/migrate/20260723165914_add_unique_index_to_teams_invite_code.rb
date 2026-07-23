class AddUniqueIndexToTeamsInviteCode < ActiveRecord::Migration[8.1]
  def change
    add_index :teams, :invite_code, unique: true
  end
end
