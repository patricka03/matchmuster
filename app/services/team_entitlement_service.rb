class TeamEntitlementService
  STANDARD_TRIAL_LENGTH =
    30.days

  FOUNDER_PLUS_LENGTH =
    8.weeks

  class << self
    def start_standard_trial!(team:, starts_at: Time.current)
      entitlement =
        team.team_entitlement ||
        team.build_team_entitlement

      entitlement.assign_attributes(
        plan: "plus",
        status: "trialing",
        source: "standard_trial",
        starts_at: starts_at,
        ends_at:
          starts_at +
          STANDARD_TRIAL_LENGTH,
        provider: nil,
        provider_subscription_id: nil,
        auto_renews: false
      )

      entitlement.save!

      entitlement
    end

    def grant_founder_plus!(
      team:,
      starts_at: Time.current
    )
      entitlement =
        team.team_entitlement ||
        team.build_team_entitlement

      entitlement.assign_attributes(
        plan: "plus",
        status: "complimentary",
        source: "founder",
        starts_at: starts_at,
        ends_at:
          starts_at +
          FOUNDER_PLUS_LENGTH,
        provider: nil,
        provider_subscription_id: nil,
        auto_renews: false
      )

      entitlement.save!

      entitlement
    end

    def expire!(team:)
      entitlement =
        team.team_entitlement

      return unless entitlement

      entitlement.update!(
        plan: "free",
        status: "expired",
        auto_renews: false
      )

      entitlement
    end
  end
end
