class AddDeduplicationKeyToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :notifications,
               :deduplication_key,
               :string

    add_index :notifications,
              [:user_id, :deduplication_key],
              unique: true,
              where: "deduplication_key IS NOT NULL",
              name: "index_notifications_on_user_and_deduplication_key"
  end
end
