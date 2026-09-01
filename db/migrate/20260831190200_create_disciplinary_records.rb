class CreateDisciplinaryRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :disciplinary_records do |t|
      t.references :team,
                   null: false,
                   foreign_key: {
                     on_delete: :cascade
                   }
      t.references :match,
                   null: false,
                   foreign_key: {
                     on_delete: :cascade
                   }
      t.references :player,
                   null: false,
                   foreign_key: {
                     to_table: :users,
                     on_delete: :cascade
                   }
      t.references :recorded_by,
                   null: true,
                   foreign_key: {
                     to_table: :users,
                     on_delete: :nullify
                   }
      t.references :match_payment,
                   null: true,
                   foreign_key: {
                     on_delete: :nullify
                   }
      t.string :card_type, null: false
      t.integer :incident_minute
      t.string :reason
      t.text :notes
      t.string :evidence_url
      t.integer :suspension_matches, null: false, default: 0
      t.integer :suspension_matches_remaining, null: false, default: 0
      t.string :appeal_status, null: false, default: "not_applicable"
      t.timestamps
    end

    add_index :disciplinary_records,
              %i[team_id player_id created_at],
              name: "index_discipline_on_team_player_and_created"

    add_check_constraint :disciplinary_records,
                         "incident_minute IS NULL OR (incident_minute >= 1 AND incident_minute <= 130)",
                         name: "disciplinary_records_minute_range"

    add_check_constraint :disciplinary_records,
                         "suspension_matches >= 0 AND suspension_matches_remaining >= 0",
                         name: "disciplinary_records_suspension_nonnegative"
  end
end
