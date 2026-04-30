class CreateActivityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_events do |t|
      t.references :user, foreign_key: true
      t.string :event_name, null: false
      t.string :controller_action
      t.string :request_method, null: false
      t.string :path, null: false
      t.integer :status
      t.string :ip_hash
      t.string :user_agent
      t.string :referrer
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :activity_events, :event_name
    add_index :activity_events, :occurred_at
    add_index :activity_events, :path
  end
end
