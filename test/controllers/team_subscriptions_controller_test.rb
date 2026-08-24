require "test_helper"

class TeamSubscriptionsControllerTest <
  ActionDispatch::IntegrationTest

  setup do
    @user_sequence = 0

    @manager =
      create_user(
        account_type: "manager"
      )

    @team =
      Team.create!(
        name:
          "Subscription Endpoint FC"
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

  test "approved team manager can view subscription details" do
    token =
      authentication_token_for(
        @manager
      )

    get endpoint,
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

    assert_equal(
      @team.id,
      body.fetch(
        "team_id"
      )
    )

    assert_equal(
      @team.billing_account_token,
      body.fetch(
        "billing_account_token"
      )
    )

    assert_match(
      Team::BILLING_ACCOUNT_TOKEN_FORMAT,
      body.fetch(
        "billing_account_token"
      )
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
      false,
      subscription.fetch(
        "plus_active"
      )
    )

    monthly_google =
      body
        .fetch(
          "products"
        )
        .fetch(
          "monthly"
        )
        .fetch(
          "google_play"
        )

    assert_equal(
      "matchmuster_plus",
      monthly_google.fetch(
        "product_id"
      )
    )

    assert_equal(
      "monthly",
      monthly_google.fetch(
        "base_plan_id"
      )
    )

    annual_apple =
      body
        .fetch(
          "products"
        )
        .fetch(
          "annual"
        )
        .fetch(
          "apple"
        )

    assert_equal(
      "matchmuster_plus_annual",
      annual_apple.fetch(
        "product_id"
      )
    )

    features =
      body.fetch(
        "plus_features"
      )

    manager_centre =
      features.find do |feature|
        feature.fetch(
          "key"
        ) ==
          "manager_centre"
      end

    assert manager_centre.present?

    assert_equal(
      "Manager Centre",
      manager_centre.fetch(
        "name"
      )
    )
  end

  test "paid subscription includes provider identity" do
    travel_to(
      @now
    ) do
      TeamEntitlementService.activate_paid_plus!(
        team: @team,
        provider: "google_play",
        provider_subscription_id:
          "endpoint-subscription-123",
        billing_period: "monthly",
        provider_product_id:
          "matchmuster_plus",
        provider_base_plan_id:
          "monthly",
        starts_at: @now,
        ends_at:
          @now + 30.days,
        auto_renews: true
      )

      token =
        authentication_token_for(
          @manager
        )

      get endpoint,
          headers: {
            "Authorization" =>
              token
          },
          as: :json

      assert_response :ok

      subscription =
        JSON
          .parse(
            response.body
          )
          .fetch(
            "subscription"
          )

      assert_equal(
        "plus",
        subscription.fetch(
          "plan"
        )
      )

      assert_equal(
        "active",
        subscription.fetch(
          "status"
        )
      )

      assert_equal(
        "google_play",
        subscription.fetch(
          "provider"
        )
      )

      assert_equal(
        "monthly",
        subscription.fetch(
          "billing_period"
        )
      )

      assert_equal(
        "endpoint-subscription-123",
        @team
          .reload
          .team_entitlement
          .provider_subscription_id
      )
    end
  end

  test "unauthenticated request is rejected" do
    get endpoint,
        as: :json

    assert_response :unauthorized
  end

  test "player cannot manage team subscription" do
    player =
      create_user(
        account_type: "player"
      )

    TeamMembership.create!(
      user: player,
      team: @team,
      role: "player",
      status: "approved",
      preferred_position: "CM"
    )

    token =
      authentication_token_for(
        player
      )

    get endpoint,
        headers: {
          "Authorization" =>
            token
        },
        as: :json

    assert_response :forbidden

    body =
      JSON.parse(
        response.body
      )

    assert_includes(
      body.fetch(
        "error"
      ),
      "Only approved team managers"
    )
  end

  test "manager from another team cannot manage subscription" do
    other_manager =
      create_user(
        account_type: "manager"
      )

    token =
      authentication_token_for(
        other_manager
      )

    get endpoint,
        headers: {
          "Authorization" =>
            token
        },
        as: :json

    assert_response :forbidden
  end

  test "missing team returns not found" do
    token =
      authentication_token_for(
        @manager
      )

    get "/teams/999999/subscription",
        headers: {
          "Authorization" =>
            token
        },
        as: :json

    assert_response :not_found

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      "Team not found",
      body.fetch(
        "error"
      )
    )
  end

  private

  def endpoint
    "/teams/#{@team.id}/subscription"
  end

  def create_user(account_type:)
    @user_sequence += 1

    user =
      User.create!(
        first_name:
          "Subscription",
        last_name:
          "User#{@user_sequence}",
        account_type:
          account_type,
        email:
          "subscription-user-#{@user_sequence}@example.com",
        password:
          "Password123!",
        password_confirmation:
          "Password123!"
      )

    if account_type == "manager"
      user.update_column(
        :manager_verification_status,
        "approved"
      )
    end

    user
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
