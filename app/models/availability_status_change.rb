class AvailabilityStatusChange < ApplicationRecord
  belongs_to :team
  belongs_to :match
  belongs_to :user

  validates :from_status, :to_status, :changed_at, presence: true
end
