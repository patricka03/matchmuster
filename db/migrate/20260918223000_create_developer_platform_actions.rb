class CreateDeveloperPlatformActions < ActiveRecord::Migration[8.1]
  def change
    create_table :developer_platform_actions do |t|
      t.references :developer,
                   null: false,
                   foreign_key: true

      t.string :action_type,
               null: false

      t.string :target_type
      t.bigint :target_id

      t.text :notes,
             null: false

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :developer_platform_actions,
              :action_type

    add_index :developer_platform_actions,
              %i[target_type target_id]

    add_index :developer_platform_actions,
              :created_at
  end
end
