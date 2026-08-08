class AddInteractionFieldsToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :notifications, :opened_at, :datetime
    add_column :notifications, :kept_at, :datetime

    add_reference :notifications,
                  :post,
                  null: true,
                  foreign_key: true
  end
end
