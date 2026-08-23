require "test_helper"

class TeamsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager =
      User.create!(
        first_name: "Subscription",
        last_name: "Manager",
        account_type: "manager",
        email:
          "subscription-manager@example.com",
        password: "Password123!",
        password_confirmation:
          "Password123!"
      )

    @manager.update_column(
      :manager_verification_status,
      "approved"
    )
  end

  test "creating team automatically starts thirty day plus trial" do
    travel_to(
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
    ) do
      token =
        authentication_token_for(
          @manager
        )

      assert_difference(
        "Team.count",
        1
      ) do
        assert_difference(
          "TeamEntitlement.count",
          1
        ) do
          post "/teams",
               params: {
                 team: {
                   name:
                     "Trial Test FC",
                   description:
                     "Subscription test team"
                 }
               },
               headers: {
                 "Authorization" =>
                   token
               },
               as: :json
        end
      end

      assert_response :created

      body =
        JSON.parse(
          response.body
        )

      team =
        Team.find(
          body.fetch("id")
        )

      entitlement =
        team.team_entitlement

      assert entitlement.present?

      assert_equal(
        "plus",
        entitlement.plan
      )

      assert_equal(
        "trialing",
        entitlement.status
      )

      assert_equal(
        "standard_trial",
        entitlement.source
      )

      assert_equal(
        Time.current,
        entitlement.starts_at
      )

      assert_equal(
        Time.current + 30.days,
        entitlement.ends_at
      )

      assert_not(
        entitlement.auto_renews
      )

      subscription =
        body.fetch(
          "subscription"
        )

      assert_equal(
        "plus",
        subscription.fetch(
          "plan"
        )
      )

      assert_equal(
        "trialing",
        subscription.fetch(
          "status"
        )
      )

      assert_equal(
        "standard_trial",
        subscription.fetch(
          "source"
        )
      )

      assert_equal(
        true,
        subscription.fetch(
          "plus_active"
        )
      )

      assert_equal(
        30,
        subscription.fetch(
          "days_remaining"
        )
      )

      assert_equal(
        false,
        subscription.fetch(
          "auto_renews"
        )
      )
    end
  end

  test "manager team without entitlement is safely reported as free" do
    team =
      create_manager_team(
        name: "Existing Free FC"
      )

    token =
      authentication_token_for(
        @manager
      )

    get "/teams/#{team.id}",
        headers: {
          "Authorization" =>
            token
        },
        as: :json

    assert_response :ok

    body =
      JSON.parse(
        response.body
      )

    subscription =
      body.fetch(
        "subscription"
      )

    assert_equal(
      "free",
      subscription.fetch(
        "plan"
      )
    )

    assert_equal(
      "free",
      subscription.fetch(
        "status"
      )
    )

    assert_equal(
      false,
      subscription.fetch(
        "plus_active"
      )
    )

    assert_nil(
      subscription[
        "days_remaining"
      ]
    )
  end

  test "expired trial is automatically reported as free" do
    team =
      create_manager_team(
        name: "Expired Trial FC"
      )

    starts_at =
      40.days.ago

    TeamEntitlementService.start_standard_trial!(
      team: team,
      starts_at: starts_at
    )

    token =
      authentication_token_for(
        @manager
      )

    get "/teams/#{team.id}",
        headers: {
          "Authorization" =>
            token
        },
        as: :json

    assert_response :ok

    body =
      JSON.parse(
        response.body
      )

    subscription =
      body.fetch(
        "subscription"
      )

    assert_equal(
      "free",
      subscription.fetch(
        "plan"
      )
    )

    assert_equal(
      "expired",
      subscription.fetch(
        "status"
      )
    )

    assert_equal(
      false,
      subscription.fetch(
        "plus_active"
      )
    )

    assert_nil(
      subscription[
        "days_remaining"
      ]
    )
  end

  private

  def create_manager_team(name:)
    team =
      Team.create!(
        name: name
      )

    TeamMembership.create!(
      user: @manager,
      team: team,
      role: "manager",
      status: "approved",
      preferred_position: "CM"
    )

    team
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

    assert token.present?,
           "Expected sign in response to contain Authorization header"

    token
  end
end
