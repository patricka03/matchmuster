class AddUniqueIndexToAvailabilities < ActiveRecord::Migration[8.1]
  def change
    add_index :availabilities, %i[match_id user_id], unique: true
  end
end
