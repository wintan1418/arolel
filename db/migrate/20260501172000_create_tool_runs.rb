class CreateToolRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :tool_runs do |t|
      t.references :user, foreign_key: true
      t.string :tool_key, null: false
      t.string :operation, null: false
      t.string :status, null: false
      t.string :input_filename
      t.bigint :input_bytes
      t.string :output_filename
      t.bigint :output_bytes
      t.string :error_message
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :tool_runs, :tool_key
    add_index :tool_runs, :operation
    add_index :tool_runs, :status
    add_index :tool_runs, :occurred_at
  end
end
