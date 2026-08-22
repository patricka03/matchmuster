class AddCoordinatesToTrainings < ActiveRecord::Migration[8.1]
  def change
    add_column :trainings,
               :latitude,
               :decimal,
               precision: 10,
               scale: 6

    add_column :trainings,
               :longitude,
               :decimal,
               precision: 10,
               scale: 6
  end
end
