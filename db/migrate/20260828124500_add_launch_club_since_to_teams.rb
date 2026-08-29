class AddLaunchClubSinceToTeams <
  ActiveRecord::Migration[8.1]

  def change
    add_column :teams,
               :launch_club_since,
               :datetime

    add_index :teams,
              :launch_club_since
  end
end
