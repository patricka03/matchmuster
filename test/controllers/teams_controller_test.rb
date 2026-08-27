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

  test "created team records the approved manager as permanent owner" do
    token =
      authentication_token_for(
        @manager
      )

    post "/teams",
         params: {
           team: {
             name: "Owned Team FC"
           }
         },
         headers: {
           "Authorization" => token
         },
         as: :json

    assert_response :created

    team =
      Team.find(
        JSON.parse(
          response.body
        ).fetch(
          "id"
        )
      )

    assert_equal @manager,
                 team.owner_user
  end

  test "free owner cannot create a second owned team" do
    primary_team =
      create_owned_manager_team(
        owner: @manager,
        name: "Primary Free FC"
      )

    token =
      authentication_token_for(
        @manager
      )

    assert_no_difference(
      "Team.count"
    ) do
      post "/teams",
           params: {
             team: {
               name: "Blocked Second FC"
             }
           },
           headers: {
             "Authorization" => token
           },
           as: :json
    end

    assert_response :forbidden

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      "multi_team_plus_required",
      body.fetch("code")
    )

    assert_equal(
      primary_team.id,
      body
        .fetch("subscription_team")
        .fetch("id")
    )
  end

  test "owner plus allows a second owned team" do
    primary_team =
      create_owned_manager_team(
        owner: @manager,
        name: "Primary Plus FC"
      )

    TeamEntitlementService.start_standard_trial!(
      team: primary_team
    )

    token =
      authentication_token_for(
        @manager
      )

    assert_difference(
      "Team.count",
      1
    ) do
      post "/teams",
           params: {
             team: {
               name: "Allowed Second FC"
             }
           },
           headers: {
             "Authorization" => token
           },
           as: :json
    end

    assert_response :created

    created_team =
      Team.find(
        JSON.parse(
          response.body
        ).fetch(
          "id"
        )
      )

    assert_equal @manager,
                 created_team.owner_user
  end

  test "co-manager cannot use their own free slot to unlock the owner's additional team" do
    owner =
      create_approved_manager(
        "owner-manager@example.com"
      )

    create_owned_manager_team(
      owner: owner,
      name: "Owner Primary FC"
    )

    owner_additional_team =
      create_owned_manager_team(
        owner: owner,
        name: "Owner Additional FC"
      )

    add_manager_membership(
      team: owner_additional_team,
      manager: @manager
    )

    token =
      authentication_token_for(
        @manager
      )

    get "/teams/#{owner_additional_team.id}",
        headers: {
          "Authorization" => token
        },
        as: :json

    assert_response :forbidden

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      "multi_team_plus_required",
      body.fetch("code")
    )

    assert_equal(
      false,
      body.fetch(
        "owned_by_current_manager"
      )
    )

    assert_equal(
      owner.id,
      body
        .fetch("owner")
        .fetch("id")
    )
  end

  test "co-manager plus cannot unlock another owner's additional team" do
    owner =
      create_approved_manager(
        "plus-bypass-owner@example.com"
      )

    create_owned_manager_team(
      owner: owner,
      name: "Bypass Owner Primary FC"
    )

    owner_additional_team =
      create_owned_manager_team(
        owner: owner,
        name: "Bypass Owner Additional FC"
      )

    add_manager_membership(
      team: owner_additional_team,
      manager: @manager
    )

    co_manager_team =
      create_owned_manager_team(
        owner: @manager,
        name: "Co-manager Plus FC"
      )

    TeamEntitlementService.start_standard_trial!(
      team: co_manager_team
    )

    token =
      authentication_token_for(
        @manager
      )

    get "/teams/#{owner_additional_team.id}",
        headers: {
          "Authorization" => token
        },
        as: :json

    assert_response :forbidden

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      owner.id,
      body
        .fetch("owner")
        .fetch("id")
    )
  end

  test "owner plus unlocks an additional team for its co-managers" do
    owner =
      create_approved_manager(
        "shared-plus-owner@example.com"
      )

    owner_primary_team =
      create_owned_manager_team(
        owner: owner,
        name: "Shared Plus Primary FC"
      )

    owner_additional_team =
      create_owned_manager_team(
        owner: owner,
        name: "Shared Plus Additional FC"
      )

    add_manager_membership(
      team: owner_additional_team,
      manager: @manager
    )

    TeamEntitlementService.start_standard_trial!(
      team: owner_primary_team
    )

    token =
      authentication_token_for(
        @manager
      )

    get "/teams/#{owner_additional_team.id}",
        headers: {
          "Authorization" => token
        },
        as: :json

    assert_response :ok

    state =
      JSON
        .parse(
          response.body
        )
        .fetch(
          "multi_team_access"
        )

    assert_equal false,
                 state.fetch("locked")

    assert_equal false,
                 state.fetch(
                   "owned_by_current_manager"
                 )
  end

  test "co-manager cannot delete a team they do not own" do
    owner =
      create_approved_manager(
        "delete-owner@example.com"
      )

    team =
      create_owned_manager_team(
        owner: owner,
        name: "Owner Protected FC"
      )

    add_manager_membership(
      team: team,
      manager: @manager
    )

    token =
      authentication_token_for(
        @manager
      )

    assert_no_difference(
      "Team.count"
    ) do
      delete "/teams/#{team.id}",
             headers: {
               "Authorization" => token
             },
             as: :json
    end

    assert_response :forbidden

    assert_equal(
      "team_owner_required",
      JSON
        .parse(
          response.body
        )
        .fetch(
          "code"
        )
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

  def create_owned_manager_team(
    owner:,
    name:
  )
    team =
      Team.create!(
        name: name,
        owner_user: owner
      )

    add_manager_membership(
      team: team,
      manager: owner
    )

    team
  end

  def add_manager_membership(
    team:,
    manager:
  )
    TeamMembership.create!(
      user: manager,
      team: team,
      role: "manager",
      status: "approved",
      preferred_position: "CM"
    )
  end

  def create_approved_manager(email)
    manager =
      User.create!(
        first_name: "Additional",
        last_name: "Manager",
        account_type: "manager",
        email: email,
        password: "Password123!",
        password_confirmation: "Password123!"
      )

    manager.update_column(
      :manager_verification_status,
      "approved"
    )

    manager
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
