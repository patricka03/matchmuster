class ReplaceCornerTakerOnSquadSelections < ActiveRecord::Migration[8.1]
  def change
    remove_column :squad_selections, :is_corner_taker, :boolean

    add_column :squad_selections, :is_left_corner_taker, :boolean, default: false, null: false
    add_column :squad_selections, :is_right_corner_taker, :boolean, default: false, null: false
  end
end
