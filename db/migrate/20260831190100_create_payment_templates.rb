class CreatePaymentTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_templates do |t|
      t.references :team,
                   null: false,
                   foreign_key: {
                     on_delete: :cascade
                   }
      t.references :created_by,
                   null: true,
                   foreign_key: {
                     to_table: :users,
                     on_delete: :nullify
                   }
      t.string :name, null: false
      t.string :payment_type, null: false
      t.string :title, null: false
      t.text :description
      t.integer :amount_pence, null: false
      t.integer :default_due_days, null: false, default: 7
      t.string :recurrence, null: false, default: "none"
      t.date :next_run_on
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :payment_templates,
              %i[team_id name],
              unique: true

    add_index :payment_templates,
              %i[active next_run_on]

    add_check_constraint :payment_templates,
                         "amount_pence > 0",
                         name: "payment_templates_amount_positive"

    add_check_constraint :payment_templates,
                         "default_due_days >= 0 AND default_due_days <= 365",
                         name: "payment_templates_due_days_range"
  end
end
