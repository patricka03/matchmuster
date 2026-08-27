require "test_helper"

class UsersTeamOwnershipControllerTest < ActionDispatch::IntegrationTest
  test "owner cannot delete account and orphan an owned team" do
    owner =
      create_manager(
        "account-owner@example.com"
      )

    co_manager =
      create_manager(
        "account-co-manager@example.com"
      )

    team =
      Team.create!(
        name: "Account Owner FC",
        owner_user: owner
      )

    add_manager(
      team: team,
      manager: owner
    )

    add_manager(
      team: team,
      manager: co_manager
    )

    token =
      authentication_token_for(
        owner
      )

    delete "/users/account",
           params: {
             current_password: "Password123!"
           },
           headers: {
             "Authorization" => token
           },
           as: :json

    assert_response :conflict

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      "owned_teams_must_be_resolved",
      body.fetch("code")
    )

    assert_equal(
      [team.name],
      body.fetch("teams")
    )

    assert_not owner.reload.deleted?
  end

  private

  def create_manager(email)
    manager =
      User.create!(
        first_name: "Account",
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

    response.headers.fetch(
      "Authorization"
    )
  end
end
