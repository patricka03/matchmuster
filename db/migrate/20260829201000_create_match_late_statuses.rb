class CreateMatchLateStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :match_late_statuses do |t|
      t.references :match, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :minutes_late, null: false
      t.string :note, limit: 160
      t.datetime :reported_at, null: false

      t.timestamps
    end

    add_index :match_late_statuses,
              %i[match_id user_id],
              unique: true

    add_check_constraint :match_late_statuses,
                         "minutes_late >= 1 AND minutes_late <= 300",
                         name: "match_late_statuses_minutes_range"
  end
end
