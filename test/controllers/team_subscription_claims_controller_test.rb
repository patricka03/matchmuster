require "test_helper"

class TeamSubscriptionClaimsControllerTest <
  ActionDispatch::IntegrationTest

  setup do
    @user_sequence = 0

    @manager =
      create_user(
        account_type:
          "manager"
      )

    @team =
      Team.create!(
        name:
          "Subscription Claims FC"
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

  test "approved manager can claim Google Play purchase" do
    travel_to(
      @now
    ) do
      token =
        authentication_token_for(
          @manager
        )

      replacement =
        successful_claim(
          provider:
            "google_play"
        )

      with_replaced_call(
        GooglePlaySubscriptionPurchaseClaimService,
        replacement
      ) do |calls|
        post google_play_endpoint,
             params: {
               purchase_token:
                 "google-controller-purchase-token"
             },
             headers: {
               "Authorization" =>
                 token
             },
             as: :json

        assert_response :ok

        assert_equal(
          1,
          calls.length
        )

        assert_equal(
          @team,
          calls
            .first
            .fetch(
              :team
            )
        )

        assert_equal(
          "google-controller-purchase-token",
          calls
            .first
            .fetch(
              :purchase_token
            )
        )
      end

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
    end
  end

  test "approved manager can claim Apple purchase" do
    travel_to(
      @now
    ) do
      token =
        authentication_token_for(
          @manager
        )

      replacement =
        successful_claim(
          provider:
            "apple"
        )

      with_replaced_call(
        AppleSubscriptionPurchaseClaimService,
        replacement
      ) do |calls|
        post apple_endpoint,
             params: {
               signed_transaction:
                 "signed-apple-controller-transaction"
             },
             headers: {
               "Authorization" =>
                 token
             },
             as: :json

        assert_response :ok

        assert_equal(
          1,
          calls.length
        )

        assert_equal(
          @team,
          calls
            .first
            .fetch(
              :team
            )
        )

        assert_equal(
          "signed-apple-controller-transaction",
          calls
            .first
            .fetch(
              :signed_transaction
            )
        )
      end

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
        "apple",
        subscription.fetch(
          "provider"
        )
      )
    end
  end

  test "missing purchase token returns bad request" do
    token =
      authentication_token_for(
        @manager
      )

    post google_play_endpoint,
         params: {},
         headers: {
           "Authorization" =>
             token
         },
         as: :json

    assert_response :bad_request

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      "invalid_subscription_request",
      body.fetch(
        "code"
      )
    )
  end

  test "invalid purchase returns unprocessable entity" do
    token =
      authentication_token_for(
        @manager
      )

    replacement =
      failing_claim(
        AppleSubscriptionPurchaseClaimService::
          AccountMismatch.new(
            "Apple purchase belongs to another account"
          )
      )

    with_replaced_call(
      AppleSubscriptionPurchaseClaimService,
      replacement
    ) do
      post apple_endpoint,
           params: {
             signed_transaction:
               "invalid-apple-transaction"
           },
           headers: {
             "Authorization" =>
               token
           },
           as: :json
    end

    assert_response :unprocessable_entity

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      "subscription_verification_failed",
      body.fetch(
        "code"
      )
    )

    refute_includes(
      response.body,
      "another account"
    )
  end

  test "purchase ownership conflict returns conflict" do
    token =
      authentication_token_for(
        @manager
      )

    replacement =
      failing_claim(
        GooglePlaySubscriptionPurchaseClaimService::
          ExistingClaimConflict.new(
            "Purchase belongs to another team"
          )
      )

    with_replaced_call(
      GooglePlaySubscriptionPurchaseClaimService,
      replacement
    ) do
      post google_play_endpoint,
           params: {
             purchase_token:
               "conflicting-google-token"
           },
           headers: {
             "Authorization" =>
               token
           },
           as: :json
    end

    assert_response :conflict

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      "subscription_ownership_conflict",
      body.fetch(
        "code"
      )
    )

    refute_includes(
      response.body,
      "another team"
    )
  end

  test "temporary provider failure returns service unavailable" do
    token =
      authentication_token_for(
        @manager
      )

    replacement =
      failing_claim(
        GooglePlayDeveloperApiClient::
          RequestFailed.new(
            "Provider credentials failed"
          )
      )

    with_replaced_call(
      GooglePlaySubscriptionPurchaseClaimService,
      replacement
    ) do
      post google_play_endpoint,
           params: {
             purchase_token:
               "temporary-google-token"
           },
           headers: {
             "Authorization" =>
               token
           },
           as: :json
    end

    assert_response :service_unavailable

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      "subscription_verification_unavailable",
      body.fetch(
        "code"
      )
    )

    refute_includes(
      response.body,
      "credentials failed"
    )
  end

  test "unauthenticated claim is rejected" do
    post google_play_endpoint,
         params: {
           purchase_token:
             "unauthenticated-token"
         },
         as: :json

    assert_response :unauthorized
  end

  test "player cannot claim team subscription" do
    player =
      create_user(
        account_type:
          "player"
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

    post google_play_endpoint,
         params: {
           purchase_token:
             "player-purchase-token"
         },
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

    assert_equal(
      "subscription_manager_required",
      body.fetch(
        "code"
      )
    )
  end

  test "manager from another team cannot claim subscription" do
    other_manager =
      create_user(
        account_type:
          "manager"
      )

    token =
      authentication_token_for(
        other_manager
      )

    post apple_endpoint,
         params: {
           signed_transaction:
             "another-manager-transaction"
         },
         headers: {
           "Authorization" =>
             token
         },
         as: :json

    assert_response :forbidden
  end

  test "approved co-manager cannot claim the owner's subscription" do
    co_manager =
      create_user(
        account_type: "manager"
      )

    TeamMembership.create!(
      user: co_manager,
      team: @team,
      role: "manager",
      status: "approved",
      preferred_position: "CM"
    )

    token =
      authentication_token_for(
        co_manager
      )

    post apple_endpoint,
         params: {
           signed_transaction:
             "co-manager-transaction"
         },
         headers: {
           "Authorization" => token
         },
         as: :json

    assert_response :forbidden

    assert_equal(
      "subscription_manager_required",
      JSON
        .parse(
          response.body
        )
        .fetch(
          "code"
        )
    )
  end

  test "owner cannot claim Plus through a secondary team" do
    primary_team =
      @team

    primary_team.update!(
      owner_user: @manager
    )

    TeamEntitlementService.activate_paid_plus!(
      team: primary_team,
      provider: "google_play",
      provider_subscription_id:
        "primary-claim-subscription",
      billing_period: "monthly",
      provider_product_id:
        "matchmuster_plus",
      provider_base_plan_id:
        "monthly",
      starts_at: Time.current,
      ends_at: Time.current + 30.days,
      auto_renews: true
    )

    @team =
      Team.create!(
        name: "Secondary Claim FC",
        owner_user: @manager
      )

    TeamMembership.create!(
      user: @manager,
      team: @team,
      role: "manager",
      status: "approved",
      preferred_position: "CM"
    )

    post google_play_endpoint,
         params: {
           purchase_token:
             "secondary-team-token"
         },
         headers: {
           "Authorization" =>
             authentication_token_for(
               @manager
             )
         },
         as: :json

    assert_response :forbidden

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      "subscription_primary_team_required",
      body.fetch(
        "code"
      )
    )

    assert_equal(
      primary_team.id,
      body
        .fetch(
          "subscription_team"
        )
        .fetch(
          "id"
        )
    )
  end

  test "missing team returns not found" do
    token =
      authentication_token_for(
        @manager
      )

    post "/teams/999999/subscription/apple/claim",
         params: {
           signed_transaction:
             "missing-team-transaction"
         },
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
      "team_not_found",
      body.fetch(
        "code"
      )
    )
  end

  private

  def google_play_endpoint
    "/teams/#{@team.id}/subscription/google_play/claim"
  end

  def apple_endpoint
    "/teams/#{@team.id}/subscription/apple/claim"
  end

  def successful_claim(provider:)
    lambda do |team:, **_arguments|
      attributes =
        if provider ==
           "google_play"
          {
            provider_product_id:
              "matchmuster_plus",
            provider_base_plan_id:
              "monthly"
          }
        else
          {
            provider_product_id:
              "matchmuster_plus_monthly",
            provider_base_plan_id:
              nil
          }
        end

      TeamEntitlementService.activate_paid_plus!(
        team: team,
        provider: provider,
        provider_subscription_id:
          "#{provider}-controller-subscription",
        billing_period: "monthly",
        provider_product_id:
          attributes.fetch(
            :provider_product_id
          ),
        provider_base_plan_id:
          attributes[
            :provider_base_plan_id
          ],
        starts_at: @now,
        ends_at:
          @now + 30.days,
        auto_renews: true
      )
    end
  end

  def failing_claim(error)
    lambda do |**_arguments|
      raise error
    end
  end

  def with_replaced_call(
    service_class,
    replacement
  )
    original =
      service_class.method(
        :call
      )

    calls = []

    service_class.define_singleton_method(
      :call
    ) do |**arguments|
      calls <<
        arguments

      replacement.call(
        **arguments
      )
    end

    yield calls

  ensure
    service_class.define_singleton_method(
      :call
    ) do |*arguments, **keywords, &block|
      original.call(
        *arguments,
        **keywords,
        &block
      )
    end
  end

  def create_user(account_type:)
    @user_sequence += 1

    user =
      User.create!(
        first_name:
          "Claim",
        last_name:
          "User#{@user_sequence}",
        account_type:
          account_type,
        email:
          "claim-user-#{@user_sequence}@example.com",
        password:
          "Password123!",
        password_confirmation:
          "Password123!"
      )

    if account_type ==
       "manager"
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
