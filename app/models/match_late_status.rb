class MatchLateStatus < ApplicationRecord
  belongs_to :match
  belongs_to :user

  validates :minutes_late,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 1,
              less_than_or_equal_to: 300
            }

  validates :note,
            length: {
              maximum: 160
            },
            allow_blank: true

  validates :user_id,
            uniqueness: {
              scope: :match_id
            }
end
