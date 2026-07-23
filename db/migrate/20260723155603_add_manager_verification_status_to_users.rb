class AddManagerVerificationStatusToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :manager_verification_status, :string, default: "pending", null: false
  end
end
