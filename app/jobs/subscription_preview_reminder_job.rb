class SubscriptionPreviewReminderJob <
  ApplicationJob

  queue_as :default

  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(
    team_id,
    expected_ends_at,
    expected_source,
    kind,
    days_remaining
  )
    team =
      Team
        .includes(
          :team_entitlement,
          :owner_user,
          team_memberships:
            :user
        )
        .find_by(
          id: team_id
        )

    return unless team

    entitlement =
      team.team_entitlement

    return unless
      current_entitlement?(
        entitlement,
        expected_ends_at,
        expected_source
      )

    owner =
      team.canonical_owner

    return unless owner

    title,
    message =
      notification_copy(
        kind: kind,
        days_remaining:
          days_remaining
      )

    notification =
      Notification.create_once!(
        user: owner,

        deduplication_key:
          deduplication_key(
            team: team,
            expected_ends_at:
              expected_ends_at,
            kind: kind,
            days_remaining:
              days_remaining
          ),

        team: team,

        title: title,
        message: message,

        notification_type:
          "subscription_preview_reminder"
      )

    return unless
      notification
        .previously_new_record?

    FirebasePushService.to_user(
      user: owner,
      title: title,
      body: message,
      data: {
        type:
          "subscription_preview_reminder",

        team_id:
          team.id
      }
    )
  end

  private

  def current_entitlement?(
    entitlement,
    expected_ends_at,
    expected_source
  )
    return false unless
      entitlement&.plus_active?

    return false unless
      entitlement.source ==
      expected_source

    expected_end =
      Time.zone.parse(
        expected_ends_at
      )

    entitlement
      .ends_at
      .to_i ==
      expected_end.to_i
  rescue ArgumentError,
         TypeError
    false
  end

  def notification_copy(
    kind:,
    days_remaining:
  )
    days =
      days_remaining.to_i

    day_word =
      days == 1 ?
        "day" :
        "days"

    if kind.to_s ==
       "launch_plus"
      return [
        "#{days} #{day_word} of Launch Plus left",

        "Your Launch Club status is permanent. Complimentary Plus ends in #{days} #{day_word}."
      ]
    end

    [
      "#{days} #{day_word} of Plus Preview left",

      if days == 1
        "Your team will stay on MatchMuster Free when the Preview ends. Keep Plus anytime."
      else
        "Keep automatic reminders, insights and recurring training with MatchMuster Plus."
      end
    ]
  end

  def deduplication_key(
    team:,
    expected_ends_at:,
    kind:,
    days_remaining:
  )
    "team:#{team.id}:" \
      "#{kind}:" \
      "#{expected_ends_at}:" \
      "#{days_remaining}d"
  end
end
