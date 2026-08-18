class TrainingAvailability < ApplicationRecord
  belongs_to :training
  belongs_to :user

  validates :status,
            presence: true,
            inclusion: {
              in: %w[
                available
                unavailable
              ]
            }

  validates :user_id,
            uniqueness: {
              scope: :training_id
            }
end
