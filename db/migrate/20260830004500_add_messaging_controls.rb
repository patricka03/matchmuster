class AddMessagingControls < ActiveRecord::Migration[8.1]
  def change
    add_column :messages,
               :edited_at,
               :datetime

    add_index :messages,
              :edited_at

    add_column :conversation_participants,
               :cleared_at,
               :datetime

    add_index :conversation_participants,
              :cleared_at
  end
end
