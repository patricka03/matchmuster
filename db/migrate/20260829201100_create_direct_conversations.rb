class CreateDirectConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :team, null: false, foreign_key: true
      t.references :created_by,
                   null: true,
                   foreign_key: {
                     to_table: :users,
                     on_delete: :nullify
                   }
      t.string :conversation_type,
               null: false,
               default: "direct"
      t.string :direct_key, null: false
      t.timestamps
    end

    add_index :conversations,
              %i[team_id direct_key],
              unique: true

    create_table :conversation_participants do |t|
      t.references :conversation,
                   null: false,
                   foreign_key: {
                     on_delete: :cascade
                   }
      t.references :user,
                   null: false,
                   foreign_key: true
      t.datetime :last_read_at
      t.timestamps
    end

    add_index :conversation_participants,
              %i[conversation_id user_id],
              unique: true,
              name: "index_conversation_participants_unique"

    create_table :messages do |t|
      t.references :conversation,
                   null: false,
                   foreign_key: {
                     on_delete: :cascade
                   }
      t.references :sender,
                   null: false,
                   foreign_key: {
                     to_table: :users
                   }
      t.text :body, null: false
      t.timestamps
    end

    add_index :messages,
              %i[conversation_id created_at]

    add_reference :notifications,
                  :conversation,
                  foreign_key: {
                    on_delete: :nullify
                  }
  end
end
