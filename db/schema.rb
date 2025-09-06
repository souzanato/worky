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

ActiveRecord::Schema[8.0].define(version: 2025_09_03_112356) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "actions", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.bigint "step_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "order"
    t.text "content"
    t.boolean "has_ai_action"
    t.string "artifact_name"
    t.boolean "has_prompt_generator"
    t.index ["step_id"], name: "index_actions_on_step_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_actions", force: :cascade do |t|
    t.string "ai_model"
    t.bigint "action_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_id"], name: "index_ai_actions_on_action_id"
  end

  create_table "artifacts", force: :cascade do |t|
    t.string "title"
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "resource_type"
    t.integer "resource_id"
    t.string "code"
    t.text "description"
  end

  create_table "clients", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "email"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.string "resource_type"
    t.bigint "resource_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id"
    t.index ["resource_type", "resource_id"], name: "index_roles_on_resource"
  end

  create_table "steps", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.bigint "workflow_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "order"
    t.index ["workflow_id"], name: "index_steps_on_workflow_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "current_role_code"
    t.string "avatar"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "users_roles", id: false, force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "role_id"
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  create_table "versions", force: :cascade do |t|
    t.string "whodunnit"
    t.datetime "created_at"
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.string "event", null: false
    t.text "object"
    t.text "object_changes"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "workflow_execution_events", force: :cascade do |t|
    t.bigint "action_id", null: false
    t.jsonb "input_data"
    t.jsonb "output_data"
    t.integer "status", default: 0, null: false
    t.bigint "workflow_execution_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_id"], name: "index_workflow_execution_events_on_action_id"
    t.index ["input_data"], name: "index_wfe_on_input", using: :gin
    t.index ["output_data"], name: "index_wfe_on_output", using: :gin
    t.index ["workflow_execution_id"], name: "index_workflow_execution_events_on_workflow_execution_id"
  end

  create_table "workflow_executions", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.bigint "user_id", null: false
    t.bigint "workflow_id", null: false
    t.bigint "current_action_id"
    t.datetime "started_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "finished_at"
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_workflow_executions_on_client_id"
    t.index ["current_action_id"], name: "index_workflow_executions_on_current_action_id"
    t.index ["started_at"], name: "index_workflow_executions_on_started_at"
    t.index ["status"], name: "index_workflow_executions_on_status"
    t.index ["user_id"], name: "index_workflow_executions_on_user_id"
    t.index ["workflow_id"], name: "index_workflow_executions_on_workflow_id"
  end

  create_table "workflows", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "actions", "steps"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_actions", "actions"
  add_foreign_key "steps", "workflows"
  add_foreign_key "workflow_execution_events", "actions"
  add_foreign_key "workflow_execution_events", "workflow_executions"
  add_foreign_key "workflow_executions", "actions", column: "current_action_id"
  add_foreign_key "workflow_executions", "clients"
  add_foreign_key "workflow_executions", "users"
  add_foreign_key "workflow_executions", "workflows"
end
