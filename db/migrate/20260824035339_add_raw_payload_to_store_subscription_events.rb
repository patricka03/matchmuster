class AddRawPayloadToStoreSubscriptionEvents <
  ActiveRecord::Migration[8.1]

  def change
    add_column :store_subscription_events,
               :raw_payload,
               :jsonb,
               null: false,
               default: {}
  end
end
