class TeamSubscriptionResponse
  class << self
    def call(
      team:,
      at: Time.current
    )
      new(
        team: team,
        at: at
      ).call
    end
  end

  def initialize(
    team:,
    at:
  )
    @team = team
    @at = at
  end

  def call
    entitlement =
      team.team_entitlement

    return free_response unless
      entitlement

    entitlement_response(
      entitlement
    )
  end

  private

  attr_reader :team,
              :at

  def free_response
    {
      plan: "free",
      status: "free",
      source: nil,
      plus_active: false,
      days_remaining: nil,
      starts_at: nil,
      ends_at: nil,
      auto_renews: false,
      billing_period: nil,
      provider: nil,
      provider_product_id: nil,
      provider_base_plan_id: nil
    }
  end

  def entitlement_response(entitlement)
    plus_active =
      entitlement.plus_active?(
        at: at
      )

    {
      plan:
        entitlement.effective_plan(
          at: at
        ),

      status:
        plus_active ?
          entitlement.status :
          "expired",

      source:
        entitlement.source,

      plus_active:
        plus_active,

      days_remaining:
        entitlement.days_remaining(
          at: at
        ),

      starts_at:
        entitlement.starts_at,

      ends_at:
        entitlement.ends_at,

      auto_renews:
        entitlement.auto_renews,

      billing_period:
        entitlement.billing_period,

      provider:
        entitlement.provider,

      provider_product_id:
        entitlement.provider_product_id,

      provider_base_plan_id:
        entitlement.provider_base_plan_id
    }
  end
end
