require "test_helper"

class NotificationEventsTest < ActiveSupport::TestCase
  setup do
    @team =
      Team.create!(
        name: "Training Notification FC"
      )

    @manager =
      User.create!(
        first_name: "Manager",
        last_name: "Tester",
        account_type: "manager",
        email: "training-manager@example.com",
        password: "Password123!",
        password_confirmation: "Password123!"
      )

    @manager.update_column(
      :manager_verification_status,
      "approved"
    )

    @player =
      User.create!(
        first_name: "Patrick",
        last_name: "Player",
        account_type: "player",
        email: "training-player@example.com",
        password: "Password123!",
        password_confirmation: "Password123!"
      )

    TeamMembership.create!(
      team: @team,
      user: @manager,
      role: "manager",
      status: "approved",
      preferred_position: "CM"
    )

    TeamMembership.create!(
      team: @team,
      user: @player,
      role: "player",
      status: "approved",
      preferred_position: "ST"
    )

    @training =
      Training.create!(
        team: @team,
        title: "Tuesday Training",
        location: "Training Ground",
        meet_time: 2.days.from_now.change(
          hour: 18,
          min: 30
        ),
        starts_at: 2.days.from_now.change(
          hour: 19,
          min: 0
        )
      )
  end

  test "training availability update notifies approved manager" do
    with_stubbed_firebase_push do
      assert_difference "@manager.notifications.count", 1 do
        NotificationEvents.training_availability_updated(
          training: @training,
          player: @player,
          status: "available"
        )
      end
    end

    notification =
      @manager
        .notifications
        .order(created_at: :desc)
        .first

    assert_equal(
      "training_availability_updated",
      notification.notification_type
    )

    assert_equal(
      "Training availability updated",
      notification.title
    )

    assert_equal(
      "Patrick Player is now available for training.",
      notification.message
    )

    assert_equal(
      @player.id,
      notification.actor_id
    )
  end

  test "training availability update does not notify player" do
    with_stubbed_firebase_push do
      assert_no_difference "@player.notifications.count" do
        NotificationEvents.training_availability_updated(
          training: @training,
          player: @player,
          status: "unavailable"
        )
      end
    end
  end

  private

  def with_stubbed_firebase_push
    original_method =
      FirebasePushService.method(:to_user)

    FirebasePushService.define_singleton_method(
      :to_user
    ) do |**_arguments|
      1
    end

    yield
  ensure
    FirebasePushService.define_singleton_method(
      :to_user
    ) do |**arguments|
      original_method.call(**arguments)
    end
  end
end
