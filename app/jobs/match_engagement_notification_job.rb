class MatchEngagementNotificationJob < ApplicationJob
  queue_as :default

  EVENTS = %w[
    squad_selection_reminder
    kickoff_reminder
    match_started
  ].freeze

  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(match_id, expected_kickoff_time, event_type)
    return unless EVENTS.include?(event_type)

    match = Match.find_by(id: match_id)

    return unless match
    return if match.cancelled_at.present?
    return unless current_schedule?(match, expected_kickoff_time)

    case event_type
    when "squad_selection_reminder"
      send_squad_selection_reminder(match, expected_kickoff_time)
    when "kickoff_reminder"
      send_match_notification(
        match,
        expected_kickoff_time,
        title: "Kickoff in 1 hour",
        message: "Your fixture against #{match.opponent} kicks off in 1 hour.",
        notification_type: "match_kickoff_reminder"
      )
    when "match_started"
      send_match_notification(
        match,
        expected_kickoff_time,
        title: "Match started",
        message: "Your fixture against #{match.opponent} is underway.",
        notification_type: "match_started"
      )
    end
  end

  private

  def current_schedule?(match, expected_kickoff_time)
    match.kickoff_time.to_i ==
      Time.zone.parse(expected_kickoff_time).to_i
  end

  def send_squad_selection_reminder(match, expected_kickoff_time)
    starter_count =
      match
        .squad_selections
        .where(selection_type: "starter")
        .count

    return if starter_count >= 11

    NotificationDelivery.to_managers_once(
      team: match.team,
      deduplication_key:
        "match:#{match.id}:starting_xi_reminder:#{expected_kickoff_time}",
      match: match,
      title: "Starting XI still needs picking",
      message:
        "Kickoff against #{match.opponent} is in 2 days. Select your starting XI.",
      notification_type: "squad_selection_reminder"
    )
  end

  def send_match_notification(
    match,
    expected_kickoff_time,
    title:,
    message:,
    notification_type:
  )
    deduplication_key =
      "match:#{match.id}:#{notification_type}:#{expected_kickoff_time}"

    NotificationDelivery.to_users_once(
      users: match.selected_players,
      deduplication_key: deduplication_key,
      team: match.team,
      match: match,
      title: title,
      message: message,
      notification_type: notification_type
    )

    NotificationDelivery.to_managers_once(
      team: match.team,
      deduplication_key: deduplication_key,
      match: match,
      title: title,
      message: message,
      notification_type: notification_type
    )
  end
end
