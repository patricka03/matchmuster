class CreateMatchAwards < ActiveRecord::Migration[8.1]
  def change
    create_table :match_awards do |t|
      t.references :match,
                   null: false,
                   foreign_key: true

      t.references :user,
                   null: false,
                   foreign_key: true

      t.string :award_type,
               null: false

      t.decimal :average_rating,
                precision: 3,
                scale: 1,
                null: false

      t.datetime :awarded_at,
                 null: false

      t.timestamps
    end

    add_index(
      :match_awards,
      [:match_id, :user_id, :award_type],
      unique: true,
      name: "index_match_awards_unique"
    )
  end
end
