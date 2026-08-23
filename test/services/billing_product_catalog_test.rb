require "test_helper"

class BillingProductCatalogTest < ActiveSupport::TestCase
  test "returns Google Play monthly product identity" do
    details =
      BillingProductCatalog.details(
        provider: "google_play",
        billing_period: "monthly"
      )

    assert_equal(
      "matchmuster_plus",
      details[:product_id]
    )

    assert_equal(
      "monthly",
      details[:base_plan_id]
    )
  end

  test "returns Google Play annual product identity" do
    details =
      BillingProductCatalog.details(
        provider: "google_play",
        billing_period: "annual"
      )

    assert_equal(
      "matchmuster_plus",
      details[:product_id]
    )

    assert_equal(
      "annual",
      details[:base_plan_id]
    )
  end

  test "returns Apple monthly product identity" do
    details =
      BillingProductCatalog.details(
        provider: "apple",
        billing_period: "monthly"
      )

    assert_equal(
      "matchmuster_plus_monthly",
      details[:product_id]
    )

    assert_nil(
      details[:base_plan_id]
    )
  end

  test "returns Apple annual product identity" do
    details =
      BillingProductCatalog.details(
        provider: "apple",
        billing_period: "annual"
      )

    assert_equal(
      "matchmuster_plus_annual",
      details[:product_id]
    )

    assert_nil(
      details[:base_plan_id]
    )
  end

  test "accepts a valid billing identity" do
    assert(
      BillingProductCatalog.valid_identity?(
        provider: "google_play",
        billing_period: "monthly",
        product_id: "matchmuster_plus",
        base_plan_id: "monthly"
      )
    )

    assert(
      BillingProductCatalog.valid_identity?(
        provider: "apple",
        billing_period: "annual",
        product_id: "matchmuster_plus_annual"
      )
    )
  end

  test "rejects an incorrect product identity" do
    assert_not(
      BillingProductCatalog.valid_identity?(
        provider: "google_play",
        billing_period: "monthly",
        product_id: "wrong-product",
        base_plan_id: "monthly"
      )
    )

    assert_not(
      BillingProductCatalog.valid_identity?(
        provider: "google_play",
        billing_period: "monthly",
        product_id: "matchmuster_plus",
        base_plan_id: "wrong-base-plan"
      )
    )
  end

  test "rejects an unsupported provider or billing period" do
    assert_not(
      BillingProductCatalog.valid_identity?(
        provider: "fake_store",
        billing_period: "monthly",
        product_id: "matchmuster_plus"
      )
    )

    assert_not(
      BillingProductCatalog.valid_identity?(
        provider: "apple",
        billing_period: "weekly",
        product_id: "matchmuster_plus_weekly"
      )
    )
  end

  test "raises when validating an unknown product" do
    assert_raises(
      BillingProductCatalog::UnknownProduct
    ) do
      BillingProductCatalog.validate_identity!(
        provider: "apple",
        billing_period: "monthly",
        product_id: "wrong-product"
      )
    end
  end
end
