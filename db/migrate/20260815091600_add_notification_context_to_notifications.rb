class AddNotificationContextToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_reference :notifications,
                  :actor,
                  null: true,
                  foreign_key: { to_table: :users }

    add_reference :notifications,
                  :team,
                  null: true,
                  foreign_key: true

    add_reference :notifications,
                  :featured_user,
                  null: true,
                  foreign_key: { to_table: :users }
  end
end
