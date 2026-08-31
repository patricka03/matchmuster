require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      first_name: "Native",
      last_name: "Push",
      account_type: "player",
      email: "notification-model-push@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  end

  test "every newly created notification triggers native push" do
    delivered = []

    with_stubbed_firebase_push(
      ->(**arguments) {
        delivered << arguments
        1
      }
    ) do
      notification = @user.notifications.create!(
        title: "Every notification",
        message: "This notification must reach the device.",
        notification_type: "app_update"
      )

      assert_equal 1, delivered.length
      assert_equal @user.id, delivered.first[:user].id
      assert_equal notification.id,
                   delivered.first.dig(:data, :notification_id)
      assert_equal "app_update",
                   delivered.first.dig(:data, :notification_type)
    end
  end

  test "push failure does not remove the in-app notification" do
    with_stubbed_firebase_push(
      ->(**) {
        raise StandardError, "Firebase unavailable"
      }
    ) do
      assert_difference "@user.notifications.count", 1 do
        notification = @user.notifications.create!(
          title: "In-app fallback",
          message: "Keep this notification in the notification centre.",
          notification_type: "app_update"
        )

        assert notification.persisted?
      end
    end
  end

  private

  def with_stubbed_firebase_push(replacement)
    original_method = FirebasePushService.method(:to_user)

    FirebasePushService.define_singleton_method(
      :to_user,
      &replacement
    )

    yield
  ensure
    FirebasePushService.define_singleton_method(
      :to_user
    ) do |**arguments|
      original_method.call(**arguments)
    end
  end
end
