require "test_helper"

class TeamBillingIdentityTest < ActiveSupport::TestCase
  test "new team receives a billing account token" do
    team =
      Team.create!(
        name: "Billing Identity FC"
      )

    assert team.billing_account_token.present?

    assert_match(
      Team::BILLING_ACCOUNT_TOKEN_FORMAT,
      team.billing_account_token
    )
  end

  test "billing account token is unique" do
    existing_team =
      Team.create!(
        name: "Existing Billing FC"
      )

    duplicate_team =
      Team.new(
        name: "Duplicate Billing FC",
        billing_account_token:
          existing_team.billing_account_token
      )

    assert_not duplicate_team.valid?

    assert_includes(
      duplicate_team.errors[
        :billing_account_token
      ],
      "has already been taken"
    )
  end

  test "supplied billing account token is preserved" do
    token = SecureRandom.uuid

    team =
      Team.create!(
        name: "Supplied Billing FC",
        billing_account_token: token
      )

    assert_equal(
      token,
      team.billing_account_token
    )
  end

  test "invalid billing account token is rejected" do
    team =
      Team.new(
        name: "Invalid Billing FC",
        billing_account_token: "not-a-uuid"
      )

    assert_not team.valid?

    assert team.errors[
      :billing_account_token
    ].present?
  end
end
