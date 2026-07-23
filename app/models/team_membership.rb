class TeamMembership < ApplicationRecord
  POSITIONS = %w[GK CB LB RB CDM CM LW RW ST].freeze

  belongs_to :team
  belongs_to :user

  validates :role, :preferred_position, :status, presence: true
  validates :role, inclusion: { in: %w(manager player)}
  validates :status, inclusion: { in: %w(pending approved rejected)}
  validates :preferred_position, inclusion: { in: POSITIONS }
  validates :user_id, uniqueness: { scope: :team_id }
end
