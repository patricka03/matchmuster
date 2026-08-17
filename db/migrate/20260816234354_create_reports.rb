class CreateReports < ActiveRecord::Migration[8.1]
  def change
    create_table :reports do |t|
      t.references :reporter,
                   null: false,
                   foreign_key: {
                     to_table: :users
                   }

      t.references :reported_user,
                   null: true,
                   foreign_key: {
                     to_table: :users
                   }

      t.references :reportable,
                   polymorphic: true,
                   null: true

      t.references :reviewed_by,
                   null: true,
                   foreign_key: {
                     to_table: :developers
                   }

      t.string :reason,
               null: false

      t.text :details

      t.string :status,
               null: false,
               default: "pending"

      t.text :moderation_notes

      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :reports,
              %i[status created_at]
  end
end
