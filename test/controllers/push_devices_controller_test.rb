require "test_helper"

class PushDevicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      first_name: "Push",
      last_name: "Tester",
      account_type: "player",
      email: "push-controller-test@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )

    @other_user = User.create!(
      first_name: "Other",
      last_name: "Tester",
      account_type: "player",
      email: "push-controller-other@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  end

  test "authenticated user can register a push device" do
    token = authentication_token_for(@user)

    assert_difference "PushDevice.count", 1 do
      post "/push_devices",
           params: {
             push_device: {
               token: "controller-android-token",
               platform: "android"
             }
           },
           headers: {
             "Authorization" => token
           },
           as: :json
    end

    assert_response :ok

    push_device =
      PushDevice.find_by!(
        token: "controller-android-token"
      )

    assert_equal @user.id,
                 push_device.user_id

    assert_equal "android",
                 push_device.platform

    body = JSON.parse(response.body)

    assert_equal(
      "Push device registered successfully.",
      body["message"]
    )

    assert_equal(
      "android",
      body.dig(
        "push_device",
        "platform"
      )
    )
  end

  test "push device registration requires authentication" do
    assert_no_difference "PushDevice.count" do
      post "/push_devices",
           params: {
             push_device: {
               token: "unauthenticated-token",
               platform: "android"
             }
           },
           as: :json
    end

    assert_response :unauthorized
  end

  test "existing token is reassigned to current user" do
    PushDevice.create!(
      user: @other_user,
      token: "reassigned-token",
      platform: "android"
    )

    token = authentication_token_for(@user)

    assert_no_difference "PushDevice.count" do
      post "/push_devices",
           params: {
             push_device: {
               token: "reassigned-token",
               platform: "android"
             }
           },
           headers: {
             "Authorization" => token
           },
           as: :json
    end

    assert_response :ok

    push_device =
      PushDevice.find_by!(
        token: "reassigned-token"
      )

    assert_equal @user.id,
                 push_device.user_id
  end

  test "invalid platform is rejected" do
    token = authentication_token_for(@user)

    assert_no_difference "PushDevice.count" do
      post "/push_devices",
           params: {
             push_device: {
               token: "invalid-platform-token",
               platform: "windows"
             }
           },
           headers: {
             "Authorization" => token
           },
           as: :json
    end

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)

    assert_includes(
      body["errors"],
      "Platform is not included in the list"
    )
  end

  test "authenticated user can remove their push device" do
    push_device =
      PushDevice.create!(
        user: @user,
        token: "delete-controller-token",
        platform: "android"
      )

    token = authentication_token_for(@user)

    assert_difference "PushDevice.count", -1 do
      delete "/push_devices",
             params: {
               push_device: {
                 token: push_device.token
               }
             },
             headers: {
               "Authorization" => token
             },
             as: :json
    end

    assert_response :ok

    body = JSON.parse(response.body)

    assert_equal(
      "Push device removed successfully.",
      body["message"]
    )
  end

  test "user cannot remove another users push device" do
    PushDevice.create!(
      user: @other_user,
      token: "other-users-token",
      platform: "android"
    )

    token = authentication_token_for(@user)

    assert_no_difference "PushDevice.count" do
      delete "/push_devices",
             params: {
               push_device: {
                 token: "other-users-token"
               }
             },
             headers: {
               "Authorization" => token
             },
             as: :json
    end

    assert_response :not_found
  end

  private

  def authentication_token_for(user)
    post "/users/sign_in",
         params: {
           user: {
             email: user.email,
             password: "Password123!"
           }
         },
         as: :json

    assert_response :ok

    token =
      response.headers[
        "Authorization"
      ]

    assert token.present?,
           "Expected sign in response to contain Authorization header"

    token
  end
end
