class CreateTrainingAvailabilities < ActiveRecord::Migration[8.1]
  def change
    create_table :training_availabilities do |t|
      t.references :training,
                   null: false,
                   foreign_key: true

      t.references :user,
                   null: false,
                   foreign_key: true

      t.string :status,
               null: false

      t.timestamps
    end

    add_index :training_availabilities,
              [:training_id, :user_id],
              unique: true
  end
end
