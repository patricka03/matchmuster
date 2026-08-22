class PushDevice < ApplicationRecord
  belongs_to :user

  validates :token,
            presence: true,
            uniqueness: true

  validates :platform,
            presence: true,
            inclusion: {
              in: %w[android ios]
            }
end
