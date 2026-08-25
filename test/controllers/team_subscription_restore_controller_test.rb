require "test_helper"

class TeamSubscriptionRestoreControllerTest <
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
          "Restore Endpoint FC"
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

  test "approved manager can restore Google Play subscription" do
    travel_to(
      @now
    ) do
      token =
        authentication_token_for(
          @manager
        )

      replacement =
        successful_restore

      with_replaced_restore_service(
        replacement
      ) do |calls|
        post endpoint,
             params: {
               provider:
                 "google_play",
               purchase_token:
                 "google-restore-controller-token"
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

        call =
          calls.first

        assert_equal(
          @team,
          call.fetch(
            :team
          )
        )

        assert_equal(
          "google_play",
          call.fetch(
            :provider
          )
        )

        assert_equal(
          "google-restore-controller-token",
          call.fetch(
            :purchase_token
          )
        )

        assert_nil(
          call.fetch(
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
        "google_play",
        subscription.fetch(
          "provider"
        )
      )
    end
  end

  test "approved manager can restore Apple subscription" do
    travel_to(
      @now
    ) do
      token =
        authentication_token_for(
          @manager
        )

      replacement =
        successful_restore

      with_replaced_restore_service(
        replacement
      ) do |calls|
        post endpoint,
             params: {
               provider:
                 "apple",
               signed_transaction:
                 "signed-apple-restore-controller-transaction"
             },
             headers: {
               "Authorization" =>
                 token
             },
             as: :json

        assert_response :ok

        call =
          calls.first

        assert_equal(
          "apple",
          call.fetch(
            :provider
          )
        )

        assert_equal(
          "signed-apple-restore-controller-transaction",
          call.fetch(
            :signed_transaction
          )
        )

        assert_nil(
          call.fetch(
            :purchase_token
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
        "apple",
        subscription.fetch(
          "provider"
        )
      )
    end
  end

  test "missing provider returns bad request" do
    token =
      authentication_token_for(
        @manager
      )

    post endpoint,
         params: {
           purchase_token:
             "missing-provider-token"
         },
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

  test "unsupported provider returns bad request" do
    token =
      authentication_token_for(
        @manager
      )

    post endpoint,
         params: {
           provider:
             "stripe",
           purchase_token:
             "unsupported-provider-token"
         },
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

    assert_includes(
      body.fetch(
        "error"
      ),
      "Unsupported subscription provider"
    )
  end

  test "missing provider purchase data returns bad request" do
    token =
      authentication_token_for(
        @manager
      )

    post endpoint,
         params: {
           provider:
             "google_play"
         },
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

  test "invalid restored purchase returns unprocessable entity" do
    token =
      authentication_token_for(
        @manager
      )

    replacement =
      failing_restore(
        AppleSubscriptionPurchaseClaimService::
          AccountMismatch.new(
            "Apple account identity does not match"
          )
      )

    with_replaced_restore_service(
      replacement
    ) do
      post endpoint,
           params: {
             provider:
               "apple",
             signed_transaction:
               "invalid-apple-restore"
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
      "identity does not match"
    )
  end

  test "restore ownership conflict returns conflict" do
    token =
      authentication_token_for(
        @manager
      )

    replacement =
      failing_restore(
        GooglePlaySubscriptionPurchaseClaimService::
          ExistingClaimConflict.new(
            "Purchase already belongs elsewhere"
          )
      )

    with_replaced_restore_service(
      replacement
    ) do
      post endpoint,
           params: {
             provider:
               "google_play",
             purchase_token:
               "conflicting-restore-token"
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
      "belongs elsewhere"
    )
  end

  test "unauthenticated restore is rejected" do
    post endpoint,
         params: {
           provider:
             "google_play",
           purchase_token:
             "unauthenticated-restore-token"
         },
         as: :json

    assert_response :unauthorized
  end

  test "player cannot restore team subscription" do
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

    post endpoint,
         params: {
           provider:
             "google_play",
           purchase_token:
             "player-restore-token"
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

  test "manager from another team cannot restore subscription" do
    other_manager =
      create_user(
        account_type:
          "manager"
      )

    token =
      authentication_token_for(
        other_manager
      )

    post endpoint,
         params: {
           provider:
             "apple",
           signed_transaction:
             "another-manager-restore"
         },
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

    post "/teams/999999/subscription/restore",
         params: {
           provider:
             "google_play",
           purchase_token:
             "missing-team-restore-token"
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

  def endpoint
    "/teams/#{@team.id}/subscription/restore"
  end

  def successful_restore
    lambda do |
      team:,
      provider:,
      **_arguments
    |
      details =
        BillingProductCatalog.details(
          provider: provider,
          billing_period:
            "monthly"
        )

      TeamEntitlementService.activate_paid_plus!(
        team: team,
        provider: provider,
        provider_subscription_id:
          "#{provider}-restored-subscription",
        billing_period:
          "monthly",
        provider_product_id:
          details.fetch(
            :product_id
          ),
        provider_base_plan_id:
          details[
            :base_plan_id
          ],
        starts_at:
          @now,
        ends_at:
          @now + 30.days,
        auto_renews:
          true
      )
    end
  end

  def failing_restore(error)
    lambda do |**_arguments|
      raise error
    end
  end

  def with_replaced_restore_service(
    replacement
  )
    original =
      TeamSubscriptionRestoreService.method(
        :call
      )

    calls = []

    TeamSubscriptionRestoreService
      .define_singleton_method(
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
    TeamSubscriptionRestoreService
      .define_singleton_method(
        :call
      ) do |
        *arguments,
        **keywords,
        &block
      |
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
          "Restore",
        last_name:
          "User#{@user_sequence}",
        account_type:
          account_type,
        email:
          "restore-user-#{@user_sequence}@example.com",
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
