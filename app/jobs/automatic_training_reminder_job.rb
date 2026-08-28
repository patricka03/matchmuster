class AutomaticTrainingReminderJob <
  ApplicationJob

  queue_as :default

  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(
    training_id,
    expected_starts_at
  )
    training =
      Training.find_by(
        id: training_id
      )

    return unless training

    return unless
      current_schedule?(
        training,
        expected_starts_at
      )

    return unless
      PlusAccess.allowed?(
        team: training.team,
        feature:
          :automatic_training_reminders
      )

    return if
      training_started?(
        training
      )

    responded_user_ids =
      training
        .training_availabilities
        .select(:user_id)

    players_to_remind =
      training
        .team
        .team_memberships
        .includes(:user)
        .where(
          role: "player",
          status: "approved"
        )
        .where.not(
          user_id:
            responded_user_ids
        )

    players_to_remind.each do |membership|
      NotificationDelivery.to_user_once(
        user: membership.user,

        deduplication_key:
          reminder_key(
            training,
            expected_starts_at
          ),

        team: training.team,
        training: training,

        title:
          "Training availability reminder",

        message:
          "Please confirm your availability for #{training.title}.",

        notification_type:
          "training_availability_reminder"
      )
    end
  end

  private

  def current_schedule?(
    training,
    expected_starts_at
  )
    training.starts_at.to_i ==
      Time.zone
        .parse(
          expected_starts_at
        )
        .to_i
  end

  def training_started?(training)
    Time.current >=
      training.starts_at
  end

  def reminder_key(
    training,
    expected_starts_at
  )
    "training:#{training.id}:" \
      "availability_reminder:" \
      "#{expected_starts_at}"
  end
end
