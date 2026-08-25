class AddRecurrenceToTrainings < ActiveRecord::Migration[8.1]
  def change
    add_column :trainings,
               :recurrence_group_id,
               :string

    add_column :trainings,
               :recurrence_sequence,
               :integer

    add_column :trainings,
               :recurrence_frequency,
               :string

    add_index :trainings,
              %i[
                team_id
                recurrence_group_id
                recurrence_sequence
              ],
              unique: true,
              where:
                "recurrence_group_id IS NOT NULL",
              name:
                "index_trainings_on_team_recurrence_sequence"
  end
end
