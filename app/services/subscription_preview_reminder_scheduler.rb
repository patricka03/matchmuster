class SubscriptionPreviewReminderScheduler
  REMINDER_DAYS = [
    7,
    1
  ].freeze

  class << self
    def call(
      team:,
      entitlement:,
      kind:
    )
      new(
        team: team,
        entitlement: entitlement,
        kind: kind
      ).call
    end
  end

  def initialize(
    team:,
    entitlement:,
    kind:
  )
    @team =
      team

    @entitlement =
      entitlement

    @kind =
      kind.to_s
  end

  def call
    return unless
      entitlement&.ends_at

    REMINDER_DAYS.each do |days|
      reminder_at =
        entitlement.ends_at -
        days.days

      next if
        reminder_at <=
        Time.current

      SubscriptionPreviewReminderJob
        .set(
          wait_until:
            reminder_at
        )
        .perform_later(
          team.id,
          entitlement
            .ends_at
            .iso8601,
          entitlement.source,
          kind,
          days
        )
    end
  end

  private

  attr_reader :team,
              :entitlement,
              :kind
end
