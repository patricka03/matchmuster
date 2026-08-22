class CreatePushDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :push_devices do |t|
      t.references :user,
                   null: false,
                   foreign_key: true

      t.text :token,
             null: false

      t.string :platform,
               null: false

      t.timestamps
    end

    add_index :push_devices,
              :token,
              unique: true
  end
end
