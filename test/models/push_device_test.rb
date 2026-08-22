require "test_helper"

class PushDeviceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      first_name: "Push",
      last_name: "Tester",
      account_type: "player",
      email: "push-device-test@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  end

  test "valid android push device" do
    push_device = PushDevice.new(
      user: @user,
      token: "android-test-token",
      platform: "android"
    )

    assert push_device.valid?
  end

  test "valid ios push device" do
    push_device = PushDevice.new(
      user: @user,
      token: "ios-test-token",
      platform: "ios"
    )

    assert push_device.valid?
  end

  test "token must be present" do
    push_device = PushDevice.new(
      user: @user,
      token: nil,
      platform: "android"
    )

    assert_not push_device.valid?
    assert_includes push_device.errors[:token],
                    "can't be blank"
  end

  test "token must be unique" do
    PushDevice.create!(
      user: @user,
      token: "duplicate-token",
      platform: "android"
    )

    duplicate =
      PushDevice.new(
        user: @user,
        token: "duplicate-token",
        platform: "android"
      )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:token],
                    "has already been taken"
  end

  test "platform must be android or ios" do
    push_device = PushDevice.new(
      user: @user,
      token: "invalid-platform-token",
      platform: "windows"
    )

    assert_not push_device.valid?
    assert_includes push_device.errors[:platform],
                    "is not included in the list"
  end
end
