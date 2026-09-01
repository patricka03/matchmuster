require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "creates one player welcome notification after signup" do
    user = nil

    assert_difference "Notification.count", 1 do
      user = create_user(
        account_type: "player",
        email: "welcome-player@example.com"
      )
    end

    notification = user.notifications.sole

    assert_equal "Welcome to MatchMuster", notification.title
    assert_equal(
      "Your player account is ready. Join your team using the invite code provided by your manager.",
      notification.message
    )
    assert_equal "account_welcome", notification.notification_type
  end

  test "creates one manager welcome notification explaining approval is pending" do
    user = nil

    assert_difference "Notification.count", 1 do
      user = create_user(
        account_type: "manager",
        email: "welcome-manager@example.com"
      )
    end

    notification = user.notifications.sole

    assert_equal "Welcome to MatchMuster", notification.title
    assert_equal(
      "Your manager account has been created and is awaiting approval. We’ll notify you as soon as it’s ready.",
      notification.message
    )
    assert_equal "manager_status_updated", notification.notification_type
  end

  test "manager approval creates a separate status notification" do
    manager = create_user(
      account_type: "manager",
      email: "approved-manager@example.com"
    )

    assert_difference "manager.notifications.count", 1 do
      manager.update!(manager_verification_status: "approved")
    end

    approval = manager.notifications.newest_first.first

    assert_equal "Manager Account Approved", approval.title
    assert_equal "manager_status_updated", approval.notification_type
  end

  private

  def create_user(account_type:, email:)
    User.create!(
      first_name: "Jordan",
      last_name: "Taylor",
      email: email,
      account_type: account_type,
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  end
end
