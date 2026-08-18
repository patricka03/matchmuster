class CreateTrainings < ActiveRecord::Migration[8.1]
  def change
    create_table :trainings do |t|
      t.references :team, null: false, foreign_key: true

      t.string :title, null: false
      t.datetime :starts_at, null: false
      t.datetime :meet_time, null: false
      t.string :location, null: false
      t.text :description

      t.timestamps
    end

    add_index :trainings, [:team_id, :starts_at]
  end
end
