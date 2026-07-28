class CreateAvailabilities < ActiveRecord::Migration[8.1]
  def change
    create_table :availabilities do |t|
      t.references :user, null: false, foreign_key: true
      t.references :match, null: false, foreign_key: true
      t.string :status

      t.timestamps
    end
  end
end
