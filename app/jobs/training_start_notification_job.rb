class TrainingStartNotificationJob < ApplicationJob
  queue_as :default

  EVENTS = %w[
    one_hour
    started
  ].freeze

  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(training_id, expected_starts_at, event_type)
    return unless EVENTS.include?(event_type)

    training = Training.find_by(id: training_id)

    return unless training
    return unless current_schedule?(training, expected_starts_at)

    title, message, notification_type =
      notification_content(training, event_type)

    deduplication_key =
      "training:#{training.id}:#{notification_type}:#{expected_starts_at}"

    NotificationDelivery.to_users_once(
      users: available_players(training),
      deduplication_key: deduplication_key,
      team: training.team,
      training: training,
      title: title,
      message: message,
      notification_type: notification_type
    )

    NotificationDelivery.to_managers_once(
      team: training.team,
      deduplication_key: deduplication_key,
      training: training,
      title: title,
      message: message,
      notification_type: notification_type
    )
  end

  private

  def current_schedule?(training, expected_starts_at)
    training.starts_at.to_i ==
      Time.zone.parse(expected_starts_at).to_i
  end

  def available_players(training)
    User
      .joins(:training_availabilities, :team_memberships)
      .where(
        training_availabilities: {
          training_id: training.id,
          status: "available"
        },
        team_memberships: {
          team_id: training.team_id,
          role: "player",
          status: "approved"
        }
      )
      .distinct
  end

  def notification_content(training, event_type)
    if event_type == "one_hour"
      [
        "Training in 1 hour",
        "#{training.title} starts in 1 hour.",
        "training_start_reminder"
      ]
    else
      [
        "Training has started",
        "#{training.title} is starting now.",
        "training_started"
      ]
    end
  end
end
