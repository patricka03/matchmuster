class CreateMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :matches do |t|
      t.references :team, null: false, foreign_key: true
      t.string :opponent
      t.string :location
      t.datetime :kickoff_time
      t.string :match_type

      t.timestamps
    end
  end
end
