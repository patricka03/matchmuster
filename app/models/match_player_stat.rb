class MatchPlayerStat < ApplicationRecord
  belongs_to :match

  belongs_to :player,
             class_name: "User"

  validates :player_id,
            uniqueness: {
              scope: :match_id,
              message: "already has stats for this match"
            }

  validates :goals,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  validates :assists,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  validates :yellow_cards,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 2
            }

  validates :red_cards,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 1
            }

  validate :player_was_selected_for_match

  private

  def player_was_selected_for_match
    return if player.blank? || match.blank?

    selected =
      match.squad_selections.exists?(
        user_id: player_id
      )

    return if selected

    errors.add(
      :player,
      "must have been selected in the matchday squad"
    )
  end
end
