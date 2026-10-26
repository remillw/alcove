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

ActiveRecord::Schema[8.1].define(version: 2026_10_27_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "characters", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.string "role", null: false
    t.string "tagline", null: false
    t.text "persona", null: false
    t.text "boundaries", null: false
    t.text "greeting", null: false
    t.jsonb "sample_lines", default: [], null: false
    t.string "traits", default: [], null: false, array: true
    t.string "model", null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "accent", default: "#E2A24B", null: false
    t.string "keepsake", default: "none", null: false
    t.jsonb "statuses", default: {}, null: false
    t.jsonb "starters", default: [], null: false
    t.jsonb "returns", default: {}, null: false
    t.jsonb "showcase", default: [], null: false
    t.jsonb "translations", default: {}, null: false
    t.index ["published", "position"], name: "index_characters_on_published_and_position"
    t.index ["slug"], name: "index_characters_on_slug", unique: true
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "character_id", null: false
    t.text "summary"
    t.bigint "summarized_until_message_id"
    t.datetime "last_message_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "suggestions", default: [], null: false
    t.index ["character_id"], name: "index_conversations_on_character_id"
    t.index ["user_id", "character_id"], name: "index_conversations_on_user_id_and_character_id", unique: true
    t.index ["user_id", "last_message_at"], name: "index_conversations_on_user_id_and_last_message_at"
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "credit_entries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "message_id"
    t.integer "amount", null: false
    t.string "kind", null: false
    t.string "idempotency_key", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["idempotency_key"], name: "index_credit_entries_on_idempotency_key", unique: true
    t.index ["message_id"], name: "index_credit_entries_on_message_id"
    t.index ["user_id", "id"], name: "index_credit_entries_on_user_id_and_id"
  end

  create_table "keepsake_items", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.string "key", null: false
    t.string "status"
    t.string "title", null: false
    t.text "detail"
    t.text "note"
    t.bigint "source_message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "key"], name: "index_keepsake_items_on_conversation_id_and_key", unique: true
    t.index ["source_message_id"], name: "index_keepsake_items_on_source_message_id"
  end

  create_table "mcp_tokens", force: :cascade do |t|
    t.string "name", null: false
    t.string "digest", null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["digest"], name: "index_mcp_tokens_on_digest", unique: true
  end

  create_table "memories", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.text "fact", null: false
    t.integer "importance", default: 1, null: false
    t.bigint "source_message_id"
    t.vector "embedding", limit: 1024
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.virtual "fact_tsv", type: :tsvector, as: "to_tsvector('simple'::regconfig, fact)", stored: true
    t.index ["conversation_id", "importance", "id"], name: "index_memories_on_conversation_id_and_importance_and_id"
    t.index ["embedding"], name: "index_memories_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["fact_tsv"], name: "index_memories_on_fact_tsv", using: :gin
    t.index ["source_message_id"], name: "index_memories_on_source_message_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.string "role", null: false
    t.text "content", default: "", null: false
    t.string "status", default: "completed", null: false
    t.string "model"
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.integer "cache_read_tokens"
    t.bigint "cost_micros"
    t.string "error_code"
    t.datetime "cancel_requested_at"
    t.uuid "client_nonce"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "part_of_id"
    t.index ["conversation_id", "client_nonce"], name: "index_messages_on_conversation_id_and_client_nonce", unique: true, where: "(client_nonce IS NOT NULL)"
    t.index ["conversation_id", "id"], name: "index_messages_on_conversation_id_and_id"
    t.index ["conversation_id"], name: "one_active_reply_per_conversation", unique: true, where: "(((role)::text = 'assistant'::text) AND ((status)::text = ANY ((ARRAY['pending'::character varying, 'streaming'::character varying])::text[])))"
    t.check_constraint "role::text = ANY (ARRAY['user'::character varying, 'assistant'::character varying]::text[])", name: "message_role"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'streaming'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'blocked'::character varying]::text[])", name: "message_status"
  end

  create_table "outbox_events", force: :cascade do |t|
    t.string "event_type", null: false
    t.text "payload", null: false
    t.datetime "created_at", null: false
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "subscription_id"
    t.string "provider", null: false
    t.string "token", null: false
    t.string "external_id"
    t.string "checkout_ref"
    t.string "product_key", null: false
    t.string "status", default: "pending", null: false
    t.integer "amount_cents", null: false
    t.string "currency", default: "EUR", null: false
    t.integer "credits", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_payments_pending_on_created_at", where: "((status)::text = 'pending'::text)"
    t.index ["provider", "external_id"], name: "index_payments_on_provider_and_external_id", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["subscription_id"], name: "index_payments_on_subscription_id"
    t.index ["token"], name: "index_payments_on_token", unique: true
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "reports", force: :cascade do |t|
    t.bigint "message_id"
    t.bigint "user_id"
    t.string "kind", null: false
    t.text "note"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.index ["message_id"], name: "index_reports_on_message_id"
    t.index ["resolved_at", "created_at"], name: "index_reports_on_resolved_at_and_created_at"
    t.index ["user_id"], name: "index_reports_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider", null: false
    t.string "external_id", null: false
    t.string "product_key", null: false
    t.string "status", default: "active", null: false
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.datetime "canceled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "external_id"], name: "index_subscriptions_on_provider_and_external_id", unique: true
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "usage_events", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "message_id"
    t.bigint "character_id"
    t.string "kind", null: false
    t.string "model", null: false
    t.integer "input_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.integer "cache_read_tokens", default: 0, null: false
    t.integer "cache_write_tokens", default: 0, null: false
    t.bigint "cost_micros", default: 0, null: false
    t.integer "latency_ms"
    t.integer "first_token_ms"
    t.string "outcome", null: false
    t.datetime "created_at", null: false
    t.string "prompt_version"
    t.index ["character_id", "created_at"], name: "index_usage_events_on_character_id_and_created_at"
    t.index ["created_at"], name: "index_usage_events_on_created_at"
    t.index ["message_id"], name: "index_usage_events_on_message_id"
    t.index ["prompt_version", "created_at"], name: "index_usage_events_on_prompt_version_and_created_at"
    t.index ["user_id", "created_at"], name: "index_usage_events_on_user_id_and_created_at"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address"
    t.string "password_digest"
    t.string "display_name"
    t.integer "credit_balance", default: 0, null: false
    t.datetime "adult_confirmed_at"
    t.datetime "registered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "locale", default: "en", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true, where: "(email_address IS NOT NULL)"
    t.check_constraint "credit_balance >= 0", name: "credit_balance_not_negative"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.string "provider", null: false
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.index ["provider", "event_id"], name: "index_webhook_events_on_provider_and_event_id", unique: true
  end

  add_foreign_key "conversations", "characters"
  add_foreign_key "conversations", "users", on_delete: :cascade
  add_foreign_key "credit_entries", "messages", on_delete: :nullify
  add_foreign_key "credit_entries", "users", on_delete: :cascade
  add_foreign_key "keepsake_items", "conversations", on_delete: :cascade
  add_foreign_key "keepsake_items", "messages", column: "source_message_id", on_delete: :nullify
  add_foreign_key "memories", "conversations", on_delete: :cascade
  add_foreign_key "memories", "messages", column: "source_message_id", on_delete: :nullify
  add_foreign_key "messages", "conversations", on_delete: :cascade
  add_foreign_key "payments", "subscriptions", on_delete: :nullify
  add_foreign_key "payments", "users", on_delete: :cascade
  add_foreign_key "reports", "messages", on_delete: :cascade
  add_foreign_key "reports", "users", on_delete: :nullify
  add_foreign_key "sessions", "users"
  add_foreign_key "subscriptions", "users", on_delete: :cascade
  add_foreign_key "usage_events", "characters"
  add_foreign_key "usage_events", "messages", on_delete: :nullify
  add_foreign_key "usage_events", "users", on_delete: :nullify
end
