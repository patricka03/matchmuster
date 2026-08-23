class BillingProductCatalog
  class UnknownProduct < ArgumentError; end

  BILLING_PERIODS = %w[
    monthly
    annual
  ].freeze

  PRODUCTS = {
    monthly: {
      google_play: {
        product_id:
          "matchmuster_plus",
        base_plan_id:
          "monthly"
      },

      apple: {
        product_id:
          "matchmuster_plus_monthly",
        base_plan_id:
          nil
      }
    },

    annual: {
      google_play: {
        product_id:
          "matchmuster_plus",
        base_plan_id:
          "annual"
      },

      apple: {
        product_id:
          "matchmuster_plus_annual",
        base_plan_id:
          nil
      }
    }
  }.freeze

  class << self
    def details(
      provider:,
      billing_period:
    )
      provider =
        provider.to_s

      billing_period =
        billing_period.to_s

      period =
        PRODUCTS[
          billing_period.to_sym
        ]

      details =
        period&.fetch(
          provider.to_sym,
          nil
        )

      return details if details

      raise UnknownProduct,
            "Unknown billing product for #{provider} / #{billing_period}"
    end

    def valid_identity?(
      provider:,
      billing_period:,
      product_id:,
      base_plan_id: nil
    )
      expected =
        details(
          provider: provider,
          billing_period:
            billing_period
        )

      expected[:product_id] ==
        product_id &&
        expected[:base_plan_id] ==
          base_plan_id
    rescue UnknownProduct
      false
    end

    def validate_identity!(
      provider:,
      billing_period:,
      product_id:,
      base_plan_id: nil
    )
      return true if
        valid_identity?(
          provider: provider,
          billing_period:
            billing_period,
          product_id:
            product_id,
          base_plan_id:
            base_plan_id
        )

      raise UnknownProduct,
            "Unknown MatchMuster billing product"
    end
  end
end
