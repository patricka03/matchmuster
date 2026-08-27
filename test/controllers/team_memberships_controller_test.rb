require "test_helper"

class TeamMembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner =
      create_manager(
        "membership-owner@example.com"
      )

    @co_manager =
      create_manager(
        "membership-co-manager@example.com"
      )

    @team =
      Team.create!(
        name: "Owner Membership FC",
        owner_user: @owner
      )

    @owner_membership =
      add_manager(
        team: @team,
        manager: @owner
      )

    add_manager(
      team: @team,
      manager: @co_manager
    )
  end

  test "owner cannot remove their permanent owner membership" do
    token =
      authentication_token_for(
        @owner
      )

    assert_no_difference(
      "TeamMembership.count"
    ) do
      delete "/team_memberships/#{@owner_membership.id}",
             headers: {
               "Authorization" => token
             },
             as: :json
    end

    assert_response :conflict

    assert_equal(
      "team_owner_membership_required",
      JSON
        .parse(
          response.body
        )
        .fetch(
          "code"
        )
    )
  end

  test "co-manager cannot remove the permanent owner" do
    token =
      authentication_token_for(
        @co_manager
      )

    assert_no_difference(
      "TeamMembership.count"
    ) do
      delete "/team_memberships/#{@owner_membership.id}",
             headers: {
               "Authorization" => token
             },
             as: :json
    end

    assert_response :conflict
  end

  test "player can still leave the team" do
    player =
      User.create!(
        first_name: "Leaving",
        last_name: "Player",
        account_type: "player",
        email: "leaving-player@example.com",
        password: "Password123!",
        password_confirmation: "Password123!"
      )

    membership =
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

    assert_difference(
      "TeamMembership.count",
      -1
    ) do
      delete "/team_memberships/#{membership.id}",
             headers: {
               "Authorization" => token
             },
             as: :json
    end

    assert_response :no_content
  end

  private

  def create_manager(email)
    manager =
      User.create!(
        first_name: "Membership",
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

  def add_manager(
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

    assert token.present?

    token
  end
end
