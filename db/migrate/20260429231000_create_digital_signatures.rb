class CreateDigitalSignatures < ActiveRecord::Migration[8.1]
  def change
    create_table :digital_signatures do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :source_text
      t.string :style_key
      t.text :image_data, null: false

      t.timestamps
    end

    add_index :digital_signatures, [ :user_id, :created_at ]
  end
end
