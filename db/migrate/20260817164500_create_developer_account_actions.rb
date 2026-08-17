class CreateDeveloperAccountActions < ActiveRecord::Migration[8.1]
  def change
    create_table :developer_account_actions do |table|
      table.references :developer,
                       null: false,
                       foreign_key: true

      table.references :target_user,
                       null: false,
                       foreign_key: {
                         to_table: :users
                       }

      table.string :action_type,
                   null: false

      table.text :notes,
                 null: false

      table.jsonb :metadata,
                  null: false,
                  default: {}

      table.timestamps
    end

    add_index :developer_account_actions,
              :action_type
  end
end
