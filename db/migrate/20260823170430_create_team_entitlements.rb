class CreateTeamEntitlements < ActiveRecord::Migration[8.1]
  def change
    create_table :team_entitlements do |t|
      t.references :team,
                   null: false,
                   foreign_key: true

      t.string :plan,
               null: false,
               default: "plus"

      t.string :status,
               null: false,
               default: "trialing"

      t.string :source,
               null: false,
               default: "standard_trial"

      t.datetime :starts_at,
                 null: false

      t.datetime :ends_at

      t.string :provider

      t.string :provider_subscription_id

      t.boolean :auto_renews,
                null: false,
                default: false

      t.timestamps
    end

    add_index :team_entitlements,
              :team_id,
              unique: true

    add_index :team_entitlements,
              :provider_subscription_id,
              unique: true,
              where:
                "provider_subscription_id IS NOT NULL"
  end
end
