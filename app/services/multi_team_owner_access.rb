class MultiTeamOwnerAccess
  FEATURE = :multi_team_manager_centre

  def initialize(
    manager:,
    at: Time.current
  )
    @manager = manager
    @at = at
  end

  def owned_teams
    @owned_teams ||=
      owned_teams_for(
        manager
      )
  end

  def primary_owned_team
    owned_teams.first
  end

  def plus_active?
    plus_active_for?(
      owner: manager
    )
  end

  def can_create_team?
    primary_owned_team.nil? ||
      plus_active?
  end

  def managed_team?(team)
    managed_team_ids.include?(
      team.id
    )
  end

  def owner_for(team)
    team.canonical_owner
  end

  def owned_by_current_manager?(team)
    team.owned_by?(
      manager
    )
  end

  def owner_primary_team(team)
    owner =
      owner_for(team)

    return nil unless owner

    owned_teams_for(
      owner
    ).first
  end

  def primary_team?(team)
    owner_primary_team(team)&.id ==
      team.id
  end

  def accessible?(team:)
    return true unless managed_team?(team)
    return true if primary_team?(team)

    owner =
      owner_for(team)

    return false unless owner

    plus_active_for?(
      owner: owner
    )
  end

  def locked?(team:)
    managed_team?(team) &&
      !accessible?(
        team: team
      )
  end

  def team_state(team:)
    owner =
      owner_for(team)

    {
      primary_team:
        primary_team?(team),

      locked:
        locked?(team: team),

      requires_plus:
        managed_team?(team) &&
          !primary_team?(team),

      owned_by_current_manager:
        owned_by_current_manager?(team),

      can_create_additional_team:
        can_create_team?,

      owner:
        owner_response(owner),

      subscription_team:
        subscription_team_response(
          owner_primary_team(team)
        )
    }
  end

  def denial_payload(
    team: nil,
    action: "access_team"
  )
    error =
      if action == "create_team"
        "MatchMuster Plus is required to add another owned team."
      elsif team &&
        !owned_by_current_manager?(team)
        "This team's owner must resume MatchMuster Plus before managers can access it."
      else
        "Resume MatchMuster Plus to access this team."
      end

    {
      error: error,
      code:
        "multi_team_plus_required",
      feature:
        FEATURE.to_s,
      action: action,
      locked_team:
        team_response(team),
      owned_by_current_manager:
        team &&
          owned_by_current_manager?(team),
      owner:
        owner_response(
          team && owner_for(team)
        ),
      subscription_team:
        subscription_team_response(
          team ?
            owner_primary_team(team) :
            primary_owned_team
        )
    }
  end

  def sort_key(team)
    if owned_by_current_manager?(team)
      position =
        owned_teams.index do |owned_team|
          owned_team.id == team.id
        end

      [0, position || owned_teams.length]
    else
      [1, team.created_at, team.id]
    end
  end

  private

  attr_reader :manager,
              :at

  def managed_team_ids
    @managed_team_ids ||=
      manager
        .team_memberships
        .where(
          role: "manager",
          status: "approved"
        )
        .pluck(
          :team_id
        )
  end

  def owned_teams_for(owner)
    @owned_teams_by_owner ||= {}

    cached_teams =
      @owned_teams_by_owner[
        owner.id
      ]

    return cached_teams if cached_teams

    persisted_teams =
      Team
        .includes(:team_entitlement)
        .where(
          owner_user_id: owner.id
        )
        .to_a

    legacy_teams =
      owner
        .team_memberships
        .includes(
          team: [
            :team_entitlement,
            {
              team_memberships: :user
            }
          ]
        )
        .where(
          role: "manager",
          status: "approved"
        )
        .map(
          &:team
        )
        .select do |team|
          team.owner_user_id.nil? &&
            team.owned_by?(owner)
        end

    @owned_teams_by_owner[
      owner.id
    ] = (
      persisted_teams +
      legacy_teams
    )
      .uniq(&:id)
      .sort_by do |team|
        [team.created_at, team.id]
      end
  end

  def plus_active_for?(owner:)
    primary_team =
      owned_teams_for(
        owner
      ).first

    return false unless primary_team

    PlusAccess.allowed?(
      team: primary_team,
      feature: FEATURE,
      at: at
    )
  end

  def owner_response(owner)
    return nil unless owner

    {
      id: owner.id,
      name:
        [
          owner.first_name,
          owner.last_name
        ]
          .compact
          .join(" ")
          .strip
    }
  end

  def team_response(team)
    return nil unless team

    {
      id: team.id,
      name: team.name
    }
  end

  def subscription_team_response(team)
    return nil unless team

    {
      id: team.id,
      name: team.name,
      subscription:
        TeamSubscriptionResponse.call(
          team: team,
          at: at
        )
    }
  end
end
