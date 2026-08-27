require "test_helper"

class MultiTeamOwnerAccessTest < ActiveSupport::TestCase
  setup do
    @owner =
      create_manager(
        "owner@example.com"
      )

    @co_manager =
      create_manager(
        "co-manager@example.com"
      )
  end

  test "owner can create their first team without plus" do
    access =
      MultiTeamOwnerAccess.new(
        manager: @owner
      )

    assert access.can_create_team?
    assert_nil access.primary_owned_team
  end

  test "owner free team is primary and additional owned team is locked" do
    primary_team =
      create_owned_team(
        owner: @owner,
        name: "Owner Primary FC"
      )

    additional_team =
      create_owned_team(
        owner: @owner,
        name: "Owner Additional FC"
      )

    access =
      MultiTeamOwnerAccess.new(
        manager: @owner
      )

    assert_equal primary_team,
                 access.primary_owned_team

    assert access.accessible?(
      team: primary_team
    )

    assert access.locked?(
      team: additional_team
    )

    assert_not access.can_create_team?
  end

  test "co-manager cannot make the owner's additional team free" do
    create_owned_team(
      owner: @owner,
      name: "Owner Primary FC"
    )

    additional_team =
      create_owned_team(
        owner: @owner,
        name: "Owner Additional FC"
      )

    add_manager(
      team: additional_team,
      manager: @co_manager
    )

    access =
      MultiTeamOwnerAccess.new(
        manager: @co_manager
      )

    assert access.can_create_team?

    assert access.locked?(
      team: additional_team
    )

    assert_not(
      access.team_state(
        team: additional_team
      ).fetch(
        :owned_by_current_manager
      )
    )
  end

  test "co-manager plus does not unlock another owner's team" do
    create_owned_team(
      owner: @owner,
      name: "Owner Primary FC"
    )

    owner_additional_team =
      create_owned_team(
        owner: @owner,
        name: "Owner Additional FC"
      )

    add_manager(
      team: owner_additional_team,
      manager: @co_manager
    )

    co_manager_team =
      create_owned_team(
        owner: @co_manager,
        name: "Co-manager Plus FC"
      )

    TeamEntitlementService.start_standard_trial!(
      team: co_manager_team
    )

    access =
      MultiTeamOwnerAccess.new(
        manager: @co_manager
      )

    assert access.plus_active?

    assert access.locked?(
      team: owner_additional_team
    )
  end

  test "owner plus unlocks additional team for every approved manager" do
    owner_primary_team =
      create_owned_team(
        owner: @owner,
        name: "Owner Plus FC"
      )

    owner_additional_team =
      create_owned_team(
        owner: @owner,
        name: "Shared Additional FC"
      )

    add_manager(
      team: owner_additional_team,
      manager: @co_manager
    )

    TeamEntitlementService.start_standard_trial!(
      team: owner_primary_team
    )

    owner_access =
      MultiTeamOwnerAccess.new(
        manager: @owner
      )

    co_manager_access =
      MultiTeamOwnerAccess.new(
        manager: @co_manager
      )

    assert owner_access.accessible?(
      team: owner_additional_team
    )

    assert co_manager_access.accessible?(
      team: owner_additional_team
    )
  end

  test "cancelled plus locks only after its paid period ends" do
    travel_to(
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
    ) do
      owner_primary_team =
        create_owned_team(
          owner: @owner,
          name: "Cancelled Owner Plus FC"
        )

      owner_additional_team =
        create_owned_team(
          owner: @owner,
          name: "Protected Owner FC"
        )

      TeamEntitlementService.start_standard_trial!(
        team: owner_primary_team
      )

      owner_primary_team
        .team_entitlement
        .update!(
          status: "cancelled",
          ends_at: 1.day.from_now
        )

      active_access =
        MultiTeamOwnerAccess.new(
          manager: @owner,
          at: Time.current
        )

      assert active_access.accessible?(
        team: owner_additional_team
      )

      expired_access =
        MultiTeamOwnerAccess.new(
          manager: @owner,
          at: 2.days.from_now
        )

      assert expired_access.locked?(
        team: owner_additional_team
      )
    end
  end

  private

  def create_manager(email)
    manager =
      User.create!(
        first_name: "Team",
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

  def create_owned_team(
    owner:,
    name:
  )
    team =
      Team.create!(
        name: name,
        owner_user: owner
      )

    add_manager(
      team: team,
      manager: owner
    )

    team
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
end
