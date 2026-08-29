class PlusAccess
  class UnknownFeature < ArgumentError; end

  FEATURES = {
    automatic_availability_reminders:
      "Automatic availability reminders",

    automatic_training_reminders:
      "Automatic training reminders",

    automatic_payment_reminders:
      "Automatic payment reminders",

    recurring_training:
      "Recurring training",

    manager_centre:
      "Manager Centre",

    player_reliability:
      "Player reliability",

    squad_health:
      "Squad health",

    injury_fitness_status:
      "Injury and fitness status",

    advanced_season_analytics:
      "Advanced season analytics",

    payment_analytics:
      "Payment analytics",

    rotation_minutes:
      "Minutes and rotation",

    tactical_read_receipts:
      "Tactical briefing read receipts",

    matchday_eta:
      "Matchday ETA",

    club_finance:
      "Club Finance",

    multi_team_manager_centre:
      "Multi-team Manager Centre",

    exports:
      "Reports and exports"
  }.freeze

  class << self
    def allowed?(
      team:,
      feature:,
      at: Time.current
    )
      feature_key =
        normalize_feature(
          feature
        )

      validate_feature!(
        feature_key
      )

      team.plus?(
        at: at
      )
    end

    def locked?(
      team:,
      feature:,
      at: Time.current
    )
      !allowed?(
        team: team,
        feature: feature,
        at: at
      )
    end

    def feature_name(feature)
      feature_key =
        normalize_feature(
          feature
        )

      validate_feature!(
        feature_key
      )

      FEATURES.fetch(
        feature_key
      )
    end

    def feature_states(
      team:,
      at: Time.current
    )
      FEATURES.map do |
        feature,
        name
      |
        available =
          allowed?(
            team: team,
            feature: feature,
            at: at
          )

        {
          key: feature.to_s,
          name: name,
          available: available,
          locked: !available
        }
      end
    end

    def denial_payload(feature:)
      feature_key =
        normalize_feature(
          feature
        )

      validate_feature!(
        feature_key
      )

      {
        error:
          "MatchMuster Plus is required for this feature.",

        code:
          "plus_required",

        feature:
          feature_key.to_s,

        feature_name:
          FEATURES.fetch(
            feature_key
          )
      }
    end

    def feature_keys
      FEATURES.keys
    end

    private

    def normalize_feature(feature)
      feature.to_sym
    end

    def validate_feature!(feature)
      return if FEATURES.key?(
        feature
      )

      raise UnknownFeature,
            "Unknown MatchMuster Plus feature: #{feature}"
    end
  end
end
