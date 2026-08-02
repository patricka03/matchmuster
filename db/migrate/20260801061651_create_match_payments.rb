class CreateMatchPayments < ActiveRecord::Migration[8.1]
  def change
    create_table :match_payments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :match, null: false, foreign_key: true

      t.integer :amount_pence, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :paid_at

      t.timestamps
    end

    add_index :match_payments, %i[match_id user_id], unique: true
  end
end
