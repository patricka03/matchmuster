class Match < ApplicationRecord
  MATCH_TYPES = %w[league cup friendly].freeze

  before_validation :normalise_match_type

  belongs_to :team

  has_many :availabilities, dependent: :destroy
  has_many :users, through: :availabilities
  has_many :squad_selections, dependent: :destroy


  validates :opponent, :match_type, :location, :kickoff_time, presence: true
  validates :match_type, inclusion: { in: MATCH_TYPES }

  validate :kickoff_time_cannot_be_in_the_past, on: :create

  private

  def normalise_match_type
    self.match_type = match_type.to_s.downcase.strip
  end

  def kickoff_time_cannot_be_in_the_past
    return if kickoff_time.blank?
     errors.add(:kickoff_time, "cannot be in the past") if kickoff_time < Time.current
  end
end
