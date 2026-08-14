class AddResultToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :team_score, :integer
    add_column :matches, :opponent_score, :integer

    add_check_constraint(
      :matches,
      "team_score >= 0",
      name: "matches_team_score_non_negative"
    )

    add_check_constraint(
      :matches,
      "opponent_score >= 0",
      name: "matches_opponent_score_non_negative"
    )
  end
end
