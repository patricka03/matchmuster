class CreateSquadAnalyticsRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :player_fitness_statuses do |t|
      t.references :team, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :updated_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :status, null: false, default: "fit"
      t.string :note, limit: 160
      t.date :expected_return_on
      t.timestamps
    end

    add_index :player_fitness_statuses,
              %i[team_id user_id],
              unique: true

    add_check_constraint :player_fitness_statuses,
                         "status IN ('fit', 'doubtful', 'injured', 'recovering')",
                         name: "player_fitness_statuses_valid_status"

    create_table :availability_status_changes do |t|
      t.references :team, null: false, foreign_key: true
      t.references :match, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :from_status, null: false
      t.string :to_status, null: false
      t.boolean :was_selected, null: false, default: false
      t.datetime :changed_at, null: false
      t.timestamps
    end

    add_index :availability_status_changes,
              %i[team_id user_id changed_at],
              name: "index_availability_changes_for_team_player"
  end
end
