class UpdateManagerVerificationStatusOnUsers < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :manager_verification_status, from: "pending", to: nil

    change_column_null :users, :manager_verification_status, true
  end
end
