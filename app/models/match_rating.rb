class MatchRating < ApplicationRecord
  belongs_to :match

  belongs_to :rater,
             class_name: "User"

  belongs_to :player,
             class_name: "User"

  validates :rating,
            presence: true,
            numericality: {
              greater_than_or_equal_to: 1.0,
              less_than_or_equal_to: 10.0
            }

  validates :player_id,
            uniqueness: {
              scope: [:match_id, :rater_id],
              message: "has already been rated by this user for this match"
            }

  validate :cannot_rate_self
  validate :rater_must_be_eligible
  validate :player_must_be_selected

  private

  def cannot_rate_self
    return if rater_id.blank? || player_id.blank?
    return unless rater_id == player_id

    errors.add(
      :player,
      "cannot be the same as the rater"
    )
  end

  def rater_must_be_eligible
    return if rater_id.blank? || match.blank?

    unless match.rating_rater_ids.include?(rater_id)
      errors.add(
        :rater,
        "must be a selected player or approved manager for this match"
      )
    end
  end

  def player_must_be_selected
    return if player_id.blank? || match.blank?

    unless match.selected_player_ids.include?(player_id)
      errors.add(
        :player,
        "must be selected in the squad for this match"
      )
    end
  end
end
