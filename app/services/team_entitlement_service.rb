class TeamEntitlementService
  STANDARD_TRIAL_LENGTH = 30.days
  FOUNDER_PLUS_LENGTH = 8.weeks

  class << self
    def start_standard_trial!(team:, starts_at: Time.current)
      entitlement = entitlement_for(team)

      entitlement.assign_attributes(
        plan: "plus",
        status: "trialing",
        source: "standard_trial",
        starts_at: starts_at,
        ends_at: starts_at + STANDARD_TRIAL_LENGTH,
        provider: nil,
        provider_subscription_id: nil,
        billing_period: nil,
        provider_product_id: nil,
        provider_base_plan_id: nil,
        auto_renews: false
      )

      entitlement.save!
      entitlement
    end

    def grant_founder_plus!(team:, starts_at: Time.current)
      entitlement = entitlement_for(team)

      entitlement.assign_attributes(
        plan: "plus",
        status: "complimentary",
        source: "founder",
        starts_at: starts_at,
        ends_at: starts_at + FOUNDER_PLUS_LENGTH,
        provider: nil,
        provider_subscription_id: nil,
        billing_period: nil,
        provider_product_id: nil,
        provider_base_plan_id: nil,
        auto_renews: false
      )

      entitlement.save!
      entitlement
    end

    def activate_paid_plus!(
      team:,
      provider:,
      provider_subscription_id:,
      billing_period:,
      provider_product_id:,
      provider_base_plan_id: nil,
      starts_at:,
      ends_at:,
      auto_renews: true
    )
      provider = provider.to_s
      billing_period = billing_period.to_s
      provider_subscription_id =
        provider_subscription_id.to_s
      provider_product_id =
        provider_product_id.to_s
      provider_base_plan_id =
        provider_base_plan_id.to_s.presence

      unless TeamEntitlement::PROVIDERS.include?(provider)
        raise ArgumentError,
              "Unsupported subscription provider: #{provider}"
      end

      BillingProductCatalog.validate_identity!(
        provider: provider,
        billing_period: billing_period,
        product_id: provider_product_id,
        base_plan_id: provider_base_plan_id
      )

      entitlement = entitlement_for(team)

      entitlement.assign_attributes(
        plan: "plus",
        status: "active",
        source: provider,
        starts_at: starts_at,
        ends_at: ends_at,
        provider: provider,
        provider_subscription_id:
          provider_subscription_id,
        billing_period: billing_period,
        provider_product_id:
          provider_product_id,
        provider_base_plan_id:
          provider_base_plan_id,
        auto_renews: auto_renews
      )

      entitlement.save!
      entitlement
    end

    def cancel_paid_plus!(team:, access_until:)
      entitlement = team.team_entitlement

      unless entitlement&.paid?
        raise ArgumentError,
              "Team does not have a paid Plus subscription"
      end

      entitlement.update!(
        plan: "plus",
        status: "cancelled",
        ends_at: access_until,
        auto_renews: false
      )

      entitlement
    end

    def start_grace_period!(team:, ends_at:)
      entitlement = team.team_entitlement

      unless entitlement&.paid?
        raise ArgumentError,
              "Team does not have a paid Plus subscription"
      end

      entitlement.update!(
        plan: "plus",
        status: "grace_period",
        ends_at: ends_at,
        auto_renews: false
      )

      entitlement
    end

    def expire!(team:)
      entitlement = team.team_entitlement

      return unless entitlement

      entitlement.update!(
        plan: "free",
        status: "expired",
        auto_renews: false
      )

      entitlement
    end

    private

    def entitlement_for(team)
      team.team_entitlement ||
        team.build_team_entitlement
    end
  end
end
