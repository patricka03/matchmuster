class AddAccountTypeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :account_type, :string
  end
end
