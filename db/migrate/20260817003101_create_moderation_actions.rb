class CreateModerationActions < ActiveRecord::Migration[8.1]
  def change
    create_table :moderation_actions do |t|
      t.references :report,
                   null: false,
                   foreign_key: true

      t.references :developer,
                   null: true,
                   foreign_key: true

      t.references :target_user,
                   null: true,
                   foreign_key: {
                     to_table: :users
                   }

      t.string :action_type,
               null: false

      t.text :notes

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :moderation_actions,
              %i[report_id created_at]
  end
end
