class AddTrainingToNotifications <
  ActiveRecord::Migration[8.1]

  def change
    add_reference :notifications,
                  :training,
                  null: true,
                  foreign_key: true
  end
end
