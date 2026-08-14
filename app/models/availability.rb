class Availability < ApplicationRecord
  STATUS = %w[available unavailable].freeze

  before_validation :normalise_status

  belongs_to :user
  belongs_to :match

  validates :status, presence: true, inclusion: { in: STATUS }
  validates :user_id, uniqueness: { scope: :match_id }

  private

  def normalise_status
    self.status = status.to_s.downcase.strip
  end
end
