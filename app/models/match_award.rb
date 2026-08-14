class MatchAward < ApplicationRecord
  AWARD_TYPES = %w[
    man_of_the_match
  ].freeze

  belongs_to :match
  belongs_to :user

  validates :award_type,
            presence: true,
            inclusion: { in: AWARD_TYPES }

  validates :average_rating,
            presence: true,
            numericality: {
              greater_than_or_equal_to: 1.0,
              less_than_or_equal_to: 10.0
            }

  validates :awarded_at,
            presence: true

  validates :user_id,
            uniqueness: {
              scope: [ :match_id, :award_type ]
            }
end
