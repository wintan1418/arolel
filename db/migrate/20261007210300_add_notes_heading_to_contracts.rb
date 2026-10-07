class AddNotesHeadingToContracts < ActiveRecord::Migration[8.1]
  def change
    add_column :contracts, :notes_heading, :string
  end
end
