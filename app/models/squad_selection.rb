class SquadSelection < ApplicationRecord
  belongs_to :user
  belongs_to :match

  SELECTION_TYPES = %w[starter substitute].freeze

  POSITIONS = %w[ GK CB LB RB LWB RWB CDM CM CAM LM RM LW RW CF ST ].freeze

  validates :selection_type, presence: true,
                             inclusion: { in: SELECTION_TYPES }

  validates :position, presence: true,
                       inclusion: { in: POSITIONS }

  validates :user_id,
            uniqueness: {
              scope: :match_id,
              message: "has already been selected for this match"
            }

  validate :player_belongs_to_match_team
  validate :player_is_available
  validate :maximum_eleven_starters
  validate :only_one_captain
  validate :only_one_penalty_taker
  validate :only_one_corner_taker
  validate :only_one_freekick_taker

  private

  def player_belongs_to_match_team
    return if user.blank? || match.blank?

    approved_member = user.team_memberships.exists?(
      team_id: match.team_id,
      role: "player",
      status: "approved"
    )

    unless approved_member
      errors.add(:user, "must be an approved player of this team")
    end
  end

  def player_is_available
    return if user.blank? || match.blank?

    available = Availability.exists?(
      user_id: user_id,
      match_id: match_id,
      status: "available"
    )

    unless available
      errors.add(:user, "must be available for this match")
    end
  end

  def maximum_eleven_starters
    return unless selection_type == "starter"
    return if match.blank?

    starters = match.squad_selections
                    .where(selection_type: "starter")
                    .where.not(id: id)

    if starters.count >= 11
      errors.add(:selection_type, "cannot exceed 11 starters")
    end
  end

  def only_one_captain
    return unless captain?
    return if match.blank?

    if match.squad_selections.where(captain: true).where.not(id: id).exists?
      errors.add(:captain, "has already been selected for this match")
    end
  end

  def only_one_penalty_taker
    return unless is_penalty_taker?
    return if match.blank?

    if match.squad_selections
            .where(is_penalty_taker: true)
            .where.not(id: id)
            .exists?
      errors.add(
        :is_penalty_taker,
        "has already been selected for this match"
      )
    end
  end

  def only_one_corner_taker
    return unless is_corner_taker?
    return if match.blank?

    if match.squad_selections
            .where(is_corner_taker: true)
            .where.not(id: id)
            .exists?
      errors.add(
        :is_corner_taker,
        "has already been selected for this match"
      )
    end
  end

  def only_one_freekick_taker
    return unless is_freekick_taker?
    return if match.blank?

    if match.squad_selections
            .where(is_freekick_taker: true)
            .where.not(id: id)
            .exists?
      errors.add(
        :is_freekick_taker,
        "has already been selected for this match"
      )
    end
  end
end
