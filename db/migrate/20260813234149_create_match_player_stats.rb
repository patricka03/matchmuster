class CreateMatchPlayerStats < ActiveRecord::Migration[8.1]
  def change
    create_table :match_player_stats do |t|
      t.references :match,
                   null: false,
                   foreign_key: true

      t.references :player,
                   null: false,
                   foreign_key: {
                     to_table: :users
                   }

      t.integer :goals,
                null: false,
                default: 0

      t.integer :assists,
                null: false,
                default: 0

      t.boolean :clean_sheet,
                null: false,
                default: false

      t.integer :yellow_cards,
                null: false,
                default: 0

      t.integer :red_cards,
                null: false,
                default: 0

      t.timestamps
    end

    add_index(
      :match_player_stats,
      [:match_id, :player_id],
      unique: true,
      name: "index_match_player_stats_unique"
    )

    add_check_constraint(
      :match_player_stats,
      "goals >= 0",
      name: "match_player_stats_goals_non_negative"
    )

    add_check_constraint(
      :match_player_stats,
      "assists >= 0",
      name: "match_player_stats_assists_non_negative"
    )

    add_check_constraint(
      :match_player_stats,
      "yellow_cards >= 0 AND yellow_cards <= 2",
      name: "match_player_stats_yellow_cards_range"
    )

    add_check_constraint(
      :match_player_stats,
      "red_cards >= 0 AND red_cards <= 1",
      name: "match_player_stats_red_cards_range"
    )
  end
end
