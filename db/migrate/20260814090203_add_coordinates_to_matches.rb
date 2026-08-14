class AddCoordinatesToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches,
               :latitude,
               :decimal,
               precision: 10,
               scale: 6

    add_column :matches,
               :longitude,
               :decimal,
               precision: 10,
               scale: 6
  end
end
