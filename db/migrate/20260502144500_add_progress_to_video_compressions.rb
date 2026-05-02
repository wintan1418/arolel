class AddProgressToVideoCompressions < ActiveRecord::Migration[8.1]
  def change
    add_column :video_compressions, :progress_percent, :integer, null: false, default: 0
    add_column :video_compressions, :status_message, :string
  end
end
