class AddMatchToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_reference :notifications, :match, null: true, foreign_key: true
  end
end
