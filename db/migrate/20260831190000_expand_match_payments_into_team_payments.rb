class ExpandMatchPaymentsIntoTeamPayments < ActiveRecord::Migration[8.1]
  def up
    add_reference :match_payments,
                  :team,
                  null: true,
                  foreign_key: {
                    on_delete: :cascade
                  }

    add_reference :match_payments,
                  :requested_by,
                  null: true,
                  foreign_key: {
                    to_table: :users,
                    on_delete: :nullify
                  }

    add_column :match_payments, :payment_type, :string,
               null: false, default: "match_sub"
    add_column :match_payments, :title, :string
    add_column :match_payments, :description, :text
    add_column :match_payments, :due_at, :datetime
    add_column :match_payments, :payment_method, :string
    add_column :match_payments, :amount_paid_pence, :integer,
               null: false, default: 0
    add_column :match_payments, :refunded_amount_pence, :integer,
               null: false, default: 0
    add_column :match_payments, :refunded_at, :datetime
    add_column :match_payments, :waived_at, :datetime
    add_column :match_payments, :cancelled_at, :datetime
    add_column :match_payments, :cash_confirmation_requested_at, :datetime
    add_column :match_payments, :viewed_at, :datetime
    add_column :match_payments, :league_settled_at, :datetime
    add_column :match_payments, :batch_key, :string

    execute <<~SQL.squish
      UPDATE match_payments
      SET team_id = matches.team_id,
          title = 'Match Subs',
          amount_paid_pence = CASE
            WHEN match_payments.status = 'paid' THEN match_payments.amount_pence
            ELSE 0
          END,
          paid_at = CASE
            WHEN match_payments.status = 'paid'
              THEN COALESCE(match_payments.paid_at, match_payments.updated_at)
            ELSE match_payments.paid_at
          END,
          payment_method = CASE
            WHEN match_payments.status = 'paid'
              AND match_payments.stripe_payment_intent_id IS NOT NULL
              THEN 'stripe'
            WHEN match_payments.status = 'paid' THEN 'cash'
            ELSE NULL
          END,
          waived_at = CASE
            WHEN match_payments.status = 'waived' THEN match_payments.updated_at
            ELSE NULL
          END,
          refunded_amount_pence = CASE
            WHEN match_payments.status = 'refunded' THEN match_payments.amount_pence
            ELSE 0
          END,
          refunded_at = CASE
            WHEN match_payments.status = 'refunded' THEN match_payments.updated_at
            ELSE NULL
          END
      FROM matches
      WHERE matches.id = match_payments.match_id
    SQL

    change_column_null :match_payments, :team_id, false
    change_column_null :match_payments, :match_id, true

    remove_index :match_payments,
                 column: %i[match_id user_id]

    add_index :match_payments,
              %i[match_id user_id payment_type],
              name: "index_match_payments_on_match_user_and_type"

    add_index :match_payments,
              %i[match_id user_id],
              unique: true,
              where: "payment_type = 'match_sub'",
              name: "index_match_payments_unique_match_sub"

    add_index :match_payments,
              %i[team_id status due_at],
              name: "index_team_payments_on_status_and_due_at"

    add_index :match_payments,
              :batch_key,
              unique: true,
              where: "batch_key IS NOT NULL"

    add_check_constraint :match_payments,
                         "amount_paid_pence >= 0 AND amount_paid_pence <= amount_pence",
                         name: "match_payments_amount_paid_range"

    add_check_constraint :match_payments,
                         "refunded_amount_pence >= 0 AND refunded_amount_pence <= amount_paid_pence",
                         name: "match_payments_refunded_amount_range"
  end

  def down
    remove_check_constraint :match_payments,
                            name: "match_payments_refunded_amount_range"
    remove_check_constraint :match_payments,
                            name: "match_payments_amount_paid_range"
    remove_index :match_payments, :batch_key
    remove_index :match_payments,
                 name: "index_team_payments_on_status_and_due_at"
    remove_index :match_payments,
                 name: "index_match_payments_on_match_user_and_type"
    remove_index :match_payments,
                 name: "index_match_payments_unique_match_sub"
    add_index :match_payments, %i[match_id user_id], unique: true

    change_column_null :match_payments, :match_id, false

    remove_column :match_payments, :batch_key
    remove_column :match_payments, :league_settled_at
    remove_column :match_payments, :viewed_at
    remove_column :match_payments, :cash_confirmation_requested_at
    remove_column :match_payments, :cancelled_at
    remove_column :match_payments, :waived_at
    remove_column :match_payments, :refunded_at
    remove_column :match_payments, :refunded_amount_pence
    remove_column :match_payments, :amount_paid_pence
    remove_column :match_payments, :payment_method
    remove_column :match_payments, :due_at
    remove_column :match_payments, :description
    remove_column :match_payments, :title
    remove_column :match_payments, :payment_type
    remove_reference :match_payments, :requested_by, foreign_key: true
    remove_reference :match_payments, :team, foreign_key: true
  end
end
