require "test_helper"

class TeamSubscriptionFeatureStatesTest <
  ActionDispatch::IntegrationTest

  setup do
    @manager =
      User.create!(
        first_name: "Feature",
        last_name: "Manager",
        account_type: "manager",
        email:
          "feature-state-manager@example.com",
        password: "Password123!",
        password_confirmation:
          "Password123!"
      )

    @manager.update_column(
      :manager_verification_status,
      "approved"
    )

    @team =
      Team.create!(
        name:
          "Feature Endpoint FC"
      )

    TeamMembership.create!(
      user: @manager,
      team: @team,
      role: "manager",
      status: "approved",
      preferred_position: "CM"
    )

    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "subscription endpoint returns locked features for free team" do
    travel_to(@now) do
      features =
        request_features

      assert_equal(
        PlusAccess::FEATURES.count,
        features.count
      )

      assert(
        features.all? do |feature|
          feature.fetch(
            "available"
          ) == false
        end
      )

      assert(
        features.all? do |feature|
          feature.fetch(
            "locked"
          ) == true
        end
      )
    end
  end

  test "subscription endpoint returns available features for Plus trial" do
    travel_to(@now) do
      TeamEntitlementService.start_standard_trial!(
        team: @team,
        starts_at: @now
      )

      features =
        request_features

      assert(
        features.all? do |feature|
          feature.fetch(
            "available"
          ) == true
        end
      )

      assert(
        features.all? do |feature|
          feature.fetch(
            "locked"
          ) == false
        end
      )
    end
  end

  test "subscription endpoint locks features after trial expires" do
    travel_to(@now) do
      TeamEntitlementService.start_standard_trial!(
        team: @team,
        starts_at:
          @now - 31.days
      )

      features =
        request_features

      assert(
        features.all? do |feature|
          feature.fetch(
            "available"
          ) == false
        end
      )

      assert(
        features.all? do |feature|
          feature.fetch(
            "locked"
          ) == true
        end
      )
    end
  end

  private

  def request_features
    token =
      authentication_token_for(
        @manager
      )

    get "/teams/#{@team.id}/subscription",
        headers: {
          "Authorization" =>
            token
        },
        as: :json

    assert_response :ok

    JSON
      .parse(
        response.body
      )
      .fetch(
        "plus_features"
      )
  end

  def authentication_token_for(user)
    post "/users/sign_in",
         params: {
           user: {
             email:
               user.email,
             password:
               "Password123!"
           }
         },
         as: :json

    assert_response :ok

    token =
      response.headers[
        "Authorization"
      ]

    assert token.present?

    token
  end
end
