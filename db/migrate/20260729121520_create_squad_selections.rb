class CreateSquadSelections < ActiveRecord::Migration[8.1]
  def change
    create_table :squad_selections do |t|
      t.references :user, null: false, foreign_key: true
      t.references :match, null: false, foreign_key: true
      t.string :selection_type
      t.string :position
      t.boolean :captain, default: false, null: false
      t.boolean :is_corner_taker, default: false, null: false
      t.boolean :is_penalty_taker, default: false, null: false
      t.boolean :is_freekick_taker, default: false, null: false

      t.timestamps
    end

    add_index :squad_selections, [:match_id, :user_id], unique: true

  end
end
