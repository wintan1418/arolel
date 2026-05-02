class CreateVideoCompressions < ActiveRecord::Migration[8.1]
  def change
    create_table :video_compressions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.string :original_filename, null: false
      t.string :content_type
      t.bigint :input_bytes, null: false
      t.bigint :output_bytes
      t.string :input_path, null: false
      t.string :output_path
      t.string :output_filename
      t.string :active_job_id
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :video_compressions, :status
    add_index :video_compressions, :active_job_id
    add_index :video_compressions, :expires_at
    add_index :video_compressions, [ :user_id, :status ]
  end
end
