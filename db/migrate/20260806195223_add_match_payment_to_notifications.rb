class AddMatchPaymentToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_reference :notifications, :match_payment, null: true, foreign_key: true
  end
end
