class PlayerFitnessStatus < ApplicationRecord
  STATUSES = %w[fit doubtful injured recovering].freeze

  belongs_to :team
  belongs_to :user
  belongs_to :updated_by, class_name: "User", optional: true

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :team_id }
  validates :note, length: { maximum: 160 }, allow_blank: true

  validate :player_is_approved_team_member

  private

  def player_is_approved_team_member
    return if user.blank? || team.blank?
    return if user.team_memberships.exists?(
      team_id: team_id,
      role: "player",
      status: "approved"
    )

    errors.add(:user, "must be an approved player of this team")
  end
end
