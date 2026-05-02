class AddOperationToVideoCompressions < ActiveRecord::Migration[8.1]
  def change
    add_column :video_compressions, :operation, :string, null: false, default: "compress-video"
    add_index :video_compressions, :operation
  end
end
