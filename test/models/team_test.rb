require "test_helper"

class TeamTest < ActiveSupport::TestCase
  test "explicit owner remains canonical when another manager is added" do
    owner =
      create_manager(
        "team-owner@example.com"
      )

    co_manager =
      create_manager(
        "team-co-manager@example.com"
      )

    team =
      Team.create!(
        name: "Permanent Owner FC",
        owner_user: owner
      )

    add_manager(
      team: team,
      manager: co_manager
    )

    assert_equal owner,
                 team.canonical_owner

    assert team.owned_by?(
      owner
    )

    assert_not team.owned_by?(
      co_manager
    )
  end

  test "legacy team falls back to its earliest approved manager" do
    first_manager =
      create_manager(
        "legacy-first@example.com"
      )

    second_manager =
      create_manager(
        "legacy-second@example.com"
      )

    team =
      Team.create!(
        name: "Legacy Owner FC"
      )

    add_manager(
      team: team,
      manager: first_manager
    )

    add_manager(
      team: team,
      manager: second_manager
    )

    assert_equal first_manager,
                 team.canonical_owner
  end

  private

  def create_manager(email)
    manager =
      User.create!(
        first_name: "Team",
        last_name: "Owner",
        account_type: "manager",
        email: email,
        password: "Password123!",
        password_confirmation:
          "Password123!"
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
      team: team,
      user: manager,
      role: "manager",
      status: "approved",
      preferred_position: "CM"
    )
  end
end
