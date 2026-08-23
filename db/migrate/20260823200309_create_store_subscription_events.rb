class CreateStoreSubscriptionEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :store_subscription_events do |t|
      t.references :team,
                   null: true,
                   foreign_key: true

      t.string :provider,
               null: false

      t.string :provider_event_id,
               null: false

      t.string :event_type,
               null: false

      t.string :environment,
               null: false

      t.string :provider_subscription_id

      t.string :processing_status,
               null: false,
               default: "pending"

      t.datetime :occurred_at

      t.datetime :processed_at

      t.text :processing_error

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :store_subscription_events,
              %i[
                provider
                provider_event_id
              ],
              unique: true,
              name:
                "idx_store_events_provider_event"

    add_index :store_subscription_events,
              %i[
                provider
                provider_subscription_id
              ],
              name:
                "idx_store_events_provider_subscription"

    add_index :store_subscription_events,
              %i[
                processing_status
                created_at
              ],
              name:
                "idx_store_events_processing_status"
  end
end
