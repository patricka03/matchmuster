class CreateTeamEntitlements < ActiveRecord::Migration[8.1]
  def change
    create_table :team_entitlements do |t|
      t.references :team,
                   null: false,
                   foreign_key: true,
                   index: {
                     unique: true
                   }

      t.string :plan,
               null: false

      t.string :status,
               null: false

      t.string :source,
               null: false

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
              :provider_subscription_id,
              unique: true,
              where:
                "provider_subscription_id IS NOT NULL"
  end
end
