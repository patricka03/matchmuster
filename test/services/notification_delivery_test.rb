require "test_helper"

class NotificationDeliveryTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      first_name: "Push",
      last_name: "Recipient",
      account_type: "player",
      email: "notification-delivery-test@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  end

  test "to_user creates in-app notification and sends native push" do
    notification = nil

    with_stubbed_firebase_push(
      ->(user:, title:, body:, data:) {
        assert_equal @user.id, user.id
        assert_equal "Test notification", title
        assert_equal "This should also trigger native push.", body
        assert_equal "fixture_created",
                     data[:notification_type]

        1
      }
    ) do
      assert_difference "@user.notifications.count", 1 do
        notification =
          NotificationDelivery.to_user(
            user: @user,
            title: "Test notification",
            message: "This should also trigger native push.",
            notification_type: "fixture_created"
          )
      end
    end

    assert notification.persisted?

    assert_equal(
      "Test notification",
      notification.title
    )

    assert_equal(
      "This should also trigger native push.",
      notification.message
    )
  end

  test "native push failure does not remove in-app notification" do
    with_stubbed_firebase_push(
      ->(**) {
        raise StandardError,
              "Firebase unavailable"
      }
    ) do
      assert_difference "@user.notifications.count", 1 do
        notification =
          NotificationDelivery.to_user(
            user: @user,
            title: "Fallback notification",
            message: "In-app notification must still exist.",
            notification_type: "fixture_created"
          )

        assert notification.persisted?
      end
    end
  end

  private

  def with_stubbed_firebase_push(replacement)
    original_method =
      FirebasePushService.method(:to_user)

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
