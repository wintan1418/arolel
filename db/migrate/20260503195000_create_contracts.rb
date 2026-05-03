class CreateContracts < ActiveRecord::Migration[8.1]
  def change
    create_table :contracts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :title, null: false
      t.string :template, null: false, default: "service"
      t.date :effective_on
      t.string :party_a_name
      t.text :party_a_address
      t.string :party_a_email
      t.string :party_b_name
      t.text :party_b_address
      t.string :party_b_email
      t.text :summary
      t.jsonb :sections, null: false, default: []
      t.text :notes
      t.string :signer_name
      t.text :signer_image_data
      t.timestamps
    end

    add_index :contracts, :slug, unique: true
    add_index :contracts, [ :user_id, :created_at ]
  end
end
