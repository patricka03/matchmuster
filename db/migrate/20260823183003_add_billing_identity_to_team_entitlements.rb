class AddBillingIdentityToTeamEntitlements < ActiveRecord::Migration[8.1]
  def change
    add_column :team_entitlements,
               :billing_period,
               :string

    add_column :team_entitlements,
               :provider_product_id,
               :string

    add_column :team_entitlements,
               :provider_base_plan_id,
               :string
  end
end
