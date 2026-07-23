class CreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams do |t|
      t.string :name
      t.string :invite_code
      t.text :description

      t.timestamps
    end
  end
end
