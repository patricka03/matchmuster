class StoreSubscriptionTeamResolver
  class ResolutionError < StandardError; end
  class MissingTeam < ResolutionError; end
  class MissingSubscriptionId < ResolutionError; end
  class InvalidAccountToken < ResolutionError; end
  class UnknownAccountToken < ResolutionError; end
  class OwnershipConflict < ResolutionError; end
  class SubscriptionNotLinked < ResolutionError; end

  ACTIVATION_EVENT_TYPES = %w[
    subscription_activated
  ].freeze

  class << self
    def call(event:)
      new(
        event: event
      ).call
    end
  end

  def initialize(event:)
    @event = event
  end

  def call
    required_subscription_id!

    token_team =
      team_from_account_token

    ensure_no_ownership_conflict!(
      token_team
    )

    team =
      event.team ||
      linked_entitlement&.team ||
      token_team

    unless team
      raise MissingTeam,
            "Could not resolve a MatchMuster team for this subscription"
    end

    ensure_subscription_matches!(
      team
    ) unless activation_event?

    if event.team_id.nil?
      event.update!(
        team: team
      )
    end

    team
  end

  private

  attr_reader :event

  def activation_event?
    ACTIVATION_EVENT_TYPES.include?(
      event.event_type
    )
  end

  def required_subscription_id!
    value =
      event
        .provider_subscription_id
        .to_s
        .strip

    return value if value.present?

    raise MissingSubscriptionId,
          "Store subscription identifier is missing"
  end

  def linked_entitlement
    return @linked_entitlement if
      defined?(
        @linked_entitlement
      )

    @linked_entitlement =
      TeamEntitlement.find_by(
        provider:
          event.provider,
        provider_subscription_id:
          required_subscription_id!
      )
  end

  def billing_account_token
    value =
      event
        .metadata[
          "billing_account_token"
        ]
        .to_s
        .strip

    return nil if value.blank?

    unless value.match?(
      Team::BILLING_ACCOUNT_TOKEN_FORMAT
    )
      raise InvalidAccountToken,
            "Verified billing account token must be a UUID"
    end

    value.downcase
  end

  def team_from_account_token
    token =
      billing_account_token

    return nil unless token

    team =
      Team.find_by(
        billing_account_token: token
      )

    return team if team

    raise UnknownAccountToken,
          "Verified billing account token does not match a team"
  end

  def ensure_no_ownership_conflict!(token_team)
    team_ids = [
      event.team_id,
      linked_entitlement&.team_id,
      token_team&.id
    ].compact.uniq

    return if team_ids.length <= 1

    raise OwnershipConflict,
          "Store subscription identity belongs to another team"
  end

  def ensure_subscription_matches!(team)
    return if
      linked_entitlement&.team_id ==
        team.id

    raise SubscriptionNotLinked,
          "Store subscription is not linked to this team"
  end
end
