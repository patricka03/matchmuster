class Match < ApplicationRecord
  MATCH_TYPES = %w[league cup friendly].freeze
  FORMATIONS = [
    "4-4-2",
    "4-4-2 Diamond",
    "4-3-3",
    "4-2-3-1",
    "4-1-4-1",
    "4-5-1",
    "4-2-4",
    "3-5-2",
    "3-4-3",
    "3-4-2-1",
    "3-1-4-2",
    "5-3-2",
    "5-4-1",
    "5-2-3"
  ].freeze

  before_validation :normalise_match_type

  belongs_to :team

  has_many :availabilities, dependent: :destroy
  has_many :users, through: :availabilities
  has_many :squad_selections, dependent: :destroy
  has_many :match_payments, dependent: :destroy
  has_many :notifications, dependent: :nullify


  validates :opponent, :match_type, :location, :kickoff_time, presence: true
  validates :match_type, inclusion: { in: MATCH_TYPES }
  validates :formation, inclusion: { in: FORMATIONS }, allow_nil: true

  validate :kickoff_time_cannot_be_in_the_past, on: :create
  validates :description, length: { maximum: 500 }, allow_blank: true

  private

  def normalise_match_type
    self.match_type = match_type.to_s.downcase.strip
  end

  def kickoff_time_cannot_be_in_the_past
    return if kickoff_time.blank?

    errors.add(:kickoff_time, "cannot be in the past") if kickoff_time < Time.current
  end
end
