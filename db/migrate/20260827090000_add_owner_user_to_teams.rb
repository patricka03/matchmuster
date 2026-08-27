class AddOwnerUserToTeams < ActiveRecord::Migration[8.1]
  def up
    add_reference :teams,
                  :owner_user,
                  foreign_key: {
                    to_table: :users
                  },
                  index: true

    execute <<~SQL.squish
      UPDATE teams
      SET owner_user_id = owners.user_id
      FROM (
        SELECT DISTINCT ON (team_id)
          team_id,
          user_id
        FROM team_memberships
        WHERE role = 'manager'
          AND status = 'approved'
        ORDER BY team_id, created_at ASC, id ASC
      ) AS owners
      WHERE teams.id = owners.team_id
        AND teams.owner_user_id IS NULL
    SQL
  end

  def down
    remove_reference :teams,
                     :owner_user,
                     foreign_key: {
                       to_table: :users
                     }
  end
end
