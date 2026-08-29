class LaunchClubService
  class << self
    def grant!(
      team:,
      starts_at: Time.current
    )
      new(
        team: team,
        starts_at: starts_at
      ).grant!
    end
  end

  def initialize(
    team:,
    starts_at:
  )
    @team =
      team

    @starts_at =
      starts_at
  end

  def grant!
    entitlement = nil

    ActiveRecord::Base.transaction do
      mark_launch_club!

      current_entitlement =
        team.team_entitlement

      if current_entitlement&.paid? &&
         current_entitlement.plus_active?
        entitlement =
          current_entitlement

        next
      end

      if current_entitlement&.founder? &&
         current_entitlement.plus_active?
        entitlement =
          current_entitlement

        next
      end

      entitlement =
        TeamEntitlementService
          .grant_founder_plus!(
            team: team,
            starts_at:
              launch_plus_starts_at(
                current_entitlement
              )
          )
    end

    if entitlement&.source ==
       "founder" &&
       entitlement.plus_active?
      SubscriptionPreviewReminderScheduler
        .call(
          team: team,
          entitlement: entitlement,
          kind:
            "launch_plus"
        )
    end

    entitlement
  end

  private

  attr_reader :team,
              :starts_at

  def mark_launch_club!
    return if
      team.launch_club_since.present?

    team.update!(
      launch_club_since:
        starts_at
    )
  end

  def launch_plus_starts_at(
    entitlement
  )
    preview_start =
      if entitlement&.source ==
         "standard_trial"
        entitlement.starts_at
      end

    if preview_start.present? &&
       preview_start +
         TeamEntitlementService::
           FOUNDER_PLUS_LENGTH >
         starts_at
      return preview_start
    end

    starts_at
  end
end
