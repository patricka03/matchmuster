class DisciplinaryRecord < ApplicationRecord
  CARD_TYPES = %w[yellow second_yellow straight_red other].freeze
  APPEAL_STATUSES = %w[not_applicable pending upheld overturned].freeze

  belongs_to :team
  belongs_to :match
  belongs_to :player, class_name: "User"
  belongs_to :recorded_by, class_name: "User", optional: true
  belongs_to :match_payment, optional: true

  validates :card_type, presence: true, inclusion: { in: CARD_TYPES }
  validates :appeal_status,
            presence: true,
            inclusion: { in: APPEAL_STATUSES }
  validates :incident_minute,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 1,
              less_than_or_equal_to: 130
            },
            allow_nil: true
  validates :suspension_matches,
            :suspension_matches_remaining,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }
  validates :reason, length: { maximum: 180 }, allow_blank: true
  validates :notes, length: { maximum: 1_000 }, allow_blank: true
  validates :evidence_url,
            format: {
              with: %r{\Ahttps?://[^\s]+\z},
              message: "must be a valid web link"
            },
            allow_blank: true

  validate :match_must_belong_to_team
  validate :player_must_be_approved_team_member
  validate :remaining_suspension_cannot_exceed_total

  scope :active_suspensions,
        -> { where("suspension_matches_remaining > 0") }

  private

  def match_must_belong_to_team
    return if match.blank? || team.blank? || match.team_id == team_id

    errors.add(:match, "must belong to this team")
  end

  def player_must_be_approved_team_member
    return if player.blank? || team.blank?
    return if player.team_memberships.exists?(
      team_id: team_id,
      role: "player",
      status: "approved"
    )

    errors.add(:player, "must be an approved player for this team")
  end

  def remaining_suspension_cannot_exceed_total
    return if suspension_matches_remaining.to_i <= suspension_matches.to_i

    errors.add(:suspension_matches_remaining, "cannot exceed the suspension")
  end
end
