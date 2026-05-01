class CreateFeedbackSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :feedback_submissions do |t|
      t.references :user, foreign_key: true
      t.string :kind, null: false
      t.string :status, null: false, default: "new"
      t.string :name
      t.string :email
      t.string :subject
      t.string :feature_area
      t.text :message, null: false
      t.boolean :willing_to_pay, null: false, default: false
      t.string :budget_range
      t.string :ip_hash
      t.string :user_agent
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :feedback_submissions, :kind
    add_index :feedback_submissions, :status
    add_index :feedback_submissions, :feature_area
    add_index :feedback_submissions, :willing_to_pay
    add_index :feedback_submissions, :occurred_at
  end
end
