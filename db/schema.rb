# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_01_185000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "activity_events", force: :cascade do |t|
    t.string "controller_action"
    t.datetime "created_at", null: false
    t.string "event_name", null: false
    t.string "ip_hash"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.string "path", null: false
    t.string "referrer"
    t.string "request_method", null: false
    t.integer "status"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id"
    t.index ["event_name"], name: "index_activity_events_on_event_name"
    t.index ["occurred_at"], name: "index_activity_events_on_occurred_at"
    t.index ["path"], name: "index_activity_events_on_path"
    t.index ["user_id"], name: "index_activity_events_on_user_id"
  end

  create_table "boards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "hosts", default: [], null: false, array: true
    t.datetime "last_accessed_at"
    t.string "manage_token", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["slug"], name: "index_boards_on_slug", unique: true
    t.index ["user_id"], name: "index_boards_on_user_id"
  end

  create_table "checks", force: :cascade do |t|
    t.bigint "board_id", null: false
    t.datetime "checked_at", null: false
    t.datetime "created_at", null: false
    t.string "host", null: false
    t.integer "http_code"
    t.integer "latency_ms"
    t.string "region"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["board_id", "host", "checked_at"], name: "index_checks_on_board_id_and_host_and_checked_at"
    t.index ["board_id"], name: "index_checks_on_board_id"
    t.index ["checked_at"], name: "index_checks_on_checked_at"
  end

  create_table "digital_signatures", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "image_data", null: false
    t.string "name", null: false
    t.string "source_text"
    t.string "style_key"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_digital_signatures_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_digital_signatures_on_user_id"
  end

  create_table "feedback_submissions", force: :cascade do |t|
    t.string "budget_range"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "feature_area"
    t.string "ip_hash"
    t.string "kind", null: false
    t.text "message", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name"
    t.datetime "occurred_at", null: false
    t.string "status", default: "new", null: false
    t.string "subject"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id"
    t.boolean "willing_to_pay", default: false, null: false
    t.index ["feature_area"], name: "index_feedback_submissions_on_feature_area"
    t.index ["kind"], name: "index_feedback_submissions_on_kind"
    t.index ["occurred_at"], name: "index_feedback_submissions_on_occurred_at"
    t.index ["status"], name: "index_feedback_submissions_on_status"
    t.index ["user_id"], name: "index_feedback_submissions_on_user_id"
    t.index ["willing_to_pay"], name: "index_feedback_submissions_on_willing_to_pay"
  end

  create_table "invoices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.date "due_on"
    t.text "from_address"
    t.string "from_email"
    t.string "from_name"
    t.date "issued_on"
    t.jsonb "line_items", default: [], null: false
    t.text "notes"
    t.string "number", null: false
    t.string "slug", null: false
    t.decimal "tax_rate", precision: 6, scale: 3, default: "0.0"
    t.string "template", default: "plain", null: false
    t.text "to_address"
    t.string "to_email"
    t.string "to_name"
    t.decimal "total_cents", precision: 14, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["slug"], name: "index_invoices_on_slug", unique: true
    t.index ["user_id", "created_at"], name: "index_invoices_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_invoices_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "tool_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_message"
    t.bigint "input_bytes"
    t.string "input_filename"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.string "operation", null: false
    t.bigint "output_bytes"
    t.string "output_filename"
    t.string "status", null: false
    t.string "tool_key", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["occurred_at"], name: "index_tool_runs_on_occurred_at"
    t.index ["operation"], name: "index_tool_runs_on_operation"
    t.index ["status"], name: "index_tool_runs_on_status"
    t.index ["tool_key"], name: "index_tool_runs_on_tool_key"
    t.index ["user_id"], name: "index_tool_runs_on_user_id"
  end

  create_table "url_sets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_accessed_at"
    t.string "manage_token", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.text "urls", default: [], null: false, array: true
    t.bigint "user_id"
    t.index ["slug"], name: "index_url_sets_on_slug", unique: true
    t.index ["user_id"], name: "index_url_sets_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.boolean "super_admin", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["super_admin"], name: "index_users_on_super_admin"
  end

  add_foreign_key "activity_events", "users"
  add_foreign_key "boards", "users"
  add_foreign_key "checks", "boards"
  add_foreign_key "digital_signatures", "users"
  add_foreign_key "feedback_submissions", "users"
  add_foreign_key "invoices", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "tool_runs", "users"
  add_foreign_key "url_sets", "users"
end
