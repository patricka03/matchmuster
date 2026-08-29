class CreateTeamFinanceEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :team_finance_entries do |t|
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
      t.references :match,
                   null: true,
                   foreign_key: {
                     on_delete: :nullify
                   }
      t.string :entry_type, null: false
      t.string :category, null: false
      t.string :description, null: false
      t.integer :amount_pence, null: false
      t.date :occurred_on, null: false
      t.timestamps
    end

    add_index :team_finance_entries,
              %i[team_id occurred_on]

    add_check_constraint :team_finance_entries,
                         "amount_pence > 0",
                         name: "team_finance_entries_amount_positive"
  end
end
