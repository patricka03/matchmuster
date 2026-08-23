class AddVerificationToStoreSubscriptionEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :store_subscription_events,
               :verification_status,
               :string,
               null: false,
               default: "pending"

    add_column :store_subscription_events,
               :verification_checked_at,
               :datetime

    add_column :store_subscription_events,
               :verification_error,
               :text

    add_index :store_subscription_events,
              %i[
                verification_status
                created_at
              ],
              name:
                "idx_store_events_verification_status"
  end
end
