require "test_helper"

class SubscriptionAccessSecurityTest <
  ActionDispatch::IntegrationTest

  setup do
    @user_sequence = 0

    @manager =
      create_user(
        account_type:
          "manager"
      )

    @other_manager =
      create_user(
        account_type:
          "manager"
      )

    @player =
      create_user(
        account_type:
          "player"
      )

    @joining_player =
      create_user(
        account_type:
          "player"
      )

    @team =
      Team.create!(
        name:
          "Subscription Security FC",
        description:
          "Primary security-test team"
      )

    @other_team =
      Team.create!(
        name:
          "Other Subscription FC"
      )

    @private_stripe_account_id =
      "acct_private_subscription_security"

    @team.update_column(
      :stripe_account_id,
      @private_stripe_account_id
    )

    create_membership(
      user: @manager,
      team: @team,
      role: "manager"
    )

    create_membership(
      user: @player,
      team: @team,
      role: "player"
    )

    create_membership(
      user: @other_manager,
      team: @other_team,
      role: "manager"
    )

    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "approved manager receives the team billing identity" do
    token =
      authentication_token_for(
        @manager
      )

    get subscription_endpoint,
        headers:
          authorization_header(
            token
          ),
        as: :json

    assert_response :ok

    body =
      parsed_response

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
  end

  test "player and another manager cannot read team subscription identity" do
    [
      @player,
      @other_manager
    ].each do |user|
      token =
        authentication_token_for(
          user
        )

      get subscription_endpoint,
          headers:
            authorization_header(
              token
            ),
          as: :json

      assert_response :forbidden

      assert_sensitive_team_values_hidden
    end
  end

  test "ordinary player team responses hide internal billing fields" do
    token =
      authentication_token_for(
        @player
      )

    get "/teams/#{@team.id}",
        headers:
          authorization_header(
            token
          ),
        as: :json

    assert_response :ok
    assert_sensitive_team_values_hidden

    team_body =
      parsed_response

    refute team_body.key?(
      "billing_account_token"
    )

    refute team_body.key?(
      "invite_code"
    )

    refute team_body.key?(
      "stripe_account_id"
    )

    get "/teams",
        headers:
          authorization_header(
            token
          ),
        as: :json

    assert_response :ok
    assert_sensitive_team_values_hidden
  end

  test "player join response exposes only public team fields" do
    token =
      authentication_token_for(
        @joining_player
      )

    post "/team_memberships/join",
         params: {
           team_membership: {
             invite_code:
               @team.invite_code,
             preferred_position:
               "CM"
           }
         },
         headers:
           authorization_header(
             token
           ),
         as: :json

    assert_response :created

    body =
      parsed_response

    public_team =
      body.fetch(
        "team"
      )

    assert_equal(
      @team.id,
      public_team.fetch(
        "id"
      )
    )

    assert_equal(
      @team.name,
      public_team.fetch(
        "name"
      )
    )

    assert_equal(
      %w[
        badge_url
        description
        id
        name
      ],
      public_team.keys.sort
    )

    assert_sensitive_team_values_hidden
  end

  test "provider subscription identifier is never returned to clients" do
    private_provider_subscription_id =
      "private-provider-subscription-security-id"

    travel_to(
      @now
    ) do
      TeamEntitlementService.activate_paid_plus!(
        team: @team,
        provider:
          "google_play",
        provider_subscription_id:
          private_provider_subscription_id,
        billing_period:
          "monthly",
        provider_product_id:
          "matchmuster_plus",
        provider_base_plan_id:
          "monthly",
        starts_at: @now,
        ends_at:
          @now +
          30.days,
        auto_renews: true
      )

      token =
        authentication_token_for(
          @manager
        )

      get subscription_endpoint,
          headers:
            authorization_header(
              token
            ),
          as: :json

      assert_response :ok

      refute_includes(
        response.body,
        private_provider_subscription_id
      )

      subscription =
        parsed_response.fetch(
          "subscription"
        )

      refute subscription.key?(
        "provider_subscription_id"
      )

      get "/teams/#{@team.id}",
          headers:
            authorization_header(
              token
            ),
          as: :json

      assert_response :ok

      refute_includes(
        response.body,
        private_provider_subscription_id
      )
    end
  end

  test "subscription endpoints reject unauthenticated requests before mutation" do
    assert_no_difference(
      "TeamEntitlement.count"
    ) do
      assert_no_difference(
        "StoreSubscriptionEvent.count"
      ) do
        get subscription_endpoint,
            as: :json

        assert_response :unauthorized

        post google_claim_endpoint,
             params: {
               purchase_token:
                 "unauthenticated-google-secret"
             },
             as: :json

        assert_response :unauthorized

        post apple_claim_endpoint,
             params: {
               signed_transaction:
                 "unauthenticated-apple-secret"
             },
             as: :json

        assert_response :unauthorized

        post restore_endpoint,
             params: {
               provider:
                 "google_play",
               purchase_token:
                 "unauthenticated-restore-secret"
             },
             as: :json

        assert_response :unauthorized
      end
    end
  end

  test "player cannot claim or restore a team subscription" do
    token =
      authentication_token_for(
        @player
      )

    assert_no_difference(
      "TeamEntitlement.count"
    ) do
      post google_claim_endpoint,
           params: {
             purchase_token:
               "player-google-secret"
           },
           headers:
             authorization_header(
               token
             ),
           as: :json

      assert_subscription_manager_required

      post apple_claim_endpoint,
           params: {
             signed_transaction:
               "player-apple-secret"
           },
           headers:
             authorization_header(
               token
             ),
           as: :json

      assert_subscription_manager_required

      post restore_endpoint,
           params: {
             provider:
               "google_play",
             purchase_token:
               "player-restore-secret"
           },
           headers:
             authorization_header(
               token
             ),
           as: :json

      assert_subscription_manager_required
    end
  end

  test "manager from another team cannot claim or restore subscription" do
    token =
      authentication_token_for(
        @other_manager
      )

    assert_no_difference(
      "TeamEntitlement.count"
    ) do
      post google_claim_endpoint,
           params: {
             purchase_token:
               "cross-team-google-secret"
           },
           headers:
             authorization_header(
               token
             ),
           as: :json

      assert_subscription_manager_required

      post restore_endpoint,
           params: {
             provider:
               "apple",
             signed_transaction:
               "cross-team-apple-secret"
           },
           headers:
             authorization_header(
               token
             ),
           as: :json

      assert_subscription_manager_required
    end

    assert_sensitive_team_values_hidden
  end

  test "unverified Apple webhook creates only a pending ledger event" do
    signed_payload =
      "unverified-security-test-apple-payload"

    assert_no_difference(
      "TeamEntitlement.count"
    ) do
      assert_difference(
        "StoreSubscriptionEvent.count",
        1
      ) do
        assert_enqueued_jobs(
          1,
          only:
            StoreSubscriptionEventVerificationJob
        ) do
          post "/subscriptions/apple/notifications",
               params: {
                 signedPayload:
                   signed_payload
               },
               as: :json
        end
      end
    end

    assert_response :accepted

    event =
      StoreSubscriptionEvent
        .order(:id)
        .last

    assert_equal(
      "apple",
      event.provider
    )

    assert event.pending?
    assert event.verification_pending?
    assert_nil event.team

    assert_equal(
      signed_payload,
      event
        .raw_payload
        .fetch(
          "signedPayload"
        )
    )
  end

  test "invalid public webhook cannot create events or entitlements" do
    assert_no_difference(
      "TeamEntitlement.count"
    ) do
      assert_no_difference(
        "StoreSubscriptionEvent.count"
      ) do
        assert_no_enqueued_jobs(
          only:
            StoreSubscriptionEventVerificationJob
        ) do
          post "/subscriptions/apple/notifications",
               params: {},
               as: :json
        end
      end
    end

    assert_response :bad_request
  end

  test "subscription secrets are filtered from parameter logs" do
    filter =
      ActiveSupport::ParameterFilter.new(
        Rails
          .application
          .config
          .filter_parameters
      )

    filtered =
      filter.filter(
        "purchase_token" =>
          "google-purchase-secret",
        "billing_account_token" =>
          "billing-account-secret",
        "signed_transaction" =>
          "apple-transaction-secret",
        "signedPayload" =>
          "apple-webhook-secret",
        "password" =>
          "password-secret",
        "ordinary_value" =>
          "visible"
      )

    %w[
      purchase_token
      billing_account_token
      signed_transaction
      signedPayload
      password
    ].each do |key|
      assert_equal(
        "[FILTERED]",
        filtered.fetch(
          key
        )
      )
    end

    assert_equal(
      "visible",
      filtered.fetch(
        "ordinary_value"
      )
    )
  end

  private

  def subscription_endpoint
    "/teams/#{@team.id}/subscription"
  end

  def google_claim_endpoint
    "/teams/#{@team.id}/subscription/google_play/claim"
  end

  def apple_claim_endpoint
    "/teams/#{@team.id}/subscription/apple/claim"
  end

  def restore_endpoint
    "/teams/#{@team.id}/subscription/restore"
  end

  def assert_subscription_manager_required
    assert_response :forbidden

    body =
      parsed_response

    assert_equal(
      "subscription_manager_required",
      body.fetch(
        "code"
      )
    )

    assert_sensitive_team_values_hidden
  end

  def assert_sensitive_team_values_hidden
    [
      @team.billing_account_token,
      @team.invite_code,
      @private_stripe_account_id
    ].each do |secret|
      refute_includes(
        response.body,
        secret
      )
    end
  end

  def parsed_response
    JSON.parse(
      response.body
    )
  end

  def authorization_header(token)
    {
      "Authorization" =>
        token
    }
  end

  def create_membership(
    user:,
    team:,
    role:
  )
    TeamMembership.create!(
      user: user,
      team: team,
      role: role,
      status: "approved",
      preferred_position: "CM"
    )
  end

  def create_user(account_type:)
    @user_sequence += 1

    user =
      User.create!(
        first_name:
          "Security",
        last_name:
          "User#{@user_sequence}",
        account_type:
          account_type,
        email:
          "subscription-security-user-#{@user_sequence}@example.com",
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
