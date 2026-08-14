class CreateMatchRatings < ActiveRecord::Migration[8.1]
  def change
    create_table :match_ratings do |t|
      t.references :match,
                   null: false,
                   foreign_key: true

      t.references :rater,
                   null: false,
                   foreign_key: { to_table: :users }

      t.references :player,
                   null: false,
                   foreign_key: { to_table: :users }

      t.decimal :rating,
                precision: 3,
                scale: 1,
                null: false

      t.text :comment

      t.timestamps
    end

    add_index(
      :match_ratings,
      [:match_id, :rater_id, :player_id],
      unique: true,
      name: "index_match_ratings_unique"
    )

    add_check_constraint(
      :match_ratings,
      "rating >= 1.0 AND rating <= 10.0",
      name: "match_ratings_rating_range"
    )

    add_check_constraint(
      :match_ratings,
      "rater_id != player_id",
      name: "match_ratings_no_self_rating"
    )
  end
end
