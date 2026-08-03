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

ActiveRecord::Schema[8.1].define(version: 2026_08_03_091624) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "availabilities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "match_id", null: false
    t.string "status"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["match_id", "user_id"], name: "index_availabilities_on_match_id_and_user_id", unique: true
    t.index ["match_id"], name: "index_availabilities_on_match_id"
    t.index ["user_id"], name: "index_availabilities_on_user_id"
  end

  create_table "match_payments", force: :cascade do |t|
    t.integer "amount_pence", null: false
    t.datetime "created_at", null: false
    t.bigint "match_id", null: false
    t.datetime "paid_at"
    t.string "status", default: "pending", null: false
    t.string "stripe_checkout_session_id"
    t.string "stripe_payment_intent_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["match_id", "user_id"], name: "index_match_payments_on_match_id_and_user_id", unique: true
    t.index ["match_id"], name: "index_match_payments_on_match_id"
    t.index ["stripe_checkout_session_id"], name: "index_match_payments_on_stripe_checkout_session_id", unique: true
    t.index ["stripe_payment_intent_id"], name: "index_match_payments_on_stripe_payment_intent_id", unique: true
    t.index ["user_id"], name: "index_match_payments_on_user_id"
  end

  create_table "matches", force: :cascade do |t|
    t.datetime "availability_reminder_sent_at"
    t.datetime "created_at", null: false
    t.datetime "kickoff_time"
    t.string "location"
    t.string "match_type"
    t.string "opponent"
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_matches_on_team_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "message"
    t.string "notification_type"
    t.boolean "read", default: false, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "post_reads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "post_id", null: false
    t.datetime "read_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["post_id", "user_id"], name: "index_post_reads_on_post_id_and_user_id", unique: true
    t.index ["post_id"], name: "index_post_reads_on_post_id"
    t.index ["user_id"], name: "index_post_reads_on_user_id"
  end

  create_table "posts", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.boolean "pinned", default: false, null: false
    t.string "post_type"
    t.bigint "team_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["team_id"], name: "index_posts_on_team_id"
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "squad_selections", force: :cascade do |t|
    t.boolean "captain", default: false, null: false
    t.datetime "created_at", null: false
    t.boolean "is_corner_taker", default: false, null: false
    t.boolean "is_freekick_taker", default: false, null: false
    t.boolean "is_penalty_taker", default: false, null: false
    t.bigint "match_id", null: false
    t.string "position"
    t.string "selection_type"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["match_id", "user_id"], name: "index_squad_selections_on_match_id_and_user_id", unique: true
    t.index ["match_id"], name: "index_squad_selections_on_match_id"
    t.index ["user_id"], name: "index_squad_selections_on_user_id"
  end

  create_table "team_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "preferred_position"
    t.string "role"
    t.string "status"
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["team_id"], name: "index_team_memberships_on_team_id"
    t.index ["user_id", "team_id"], name: "index_team_memberships_on_user_id_and_team_id", unique: true
    t.index ["user_id"], name: "index_team_memberships_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "invite_code"
    t.string "name"
    t.string "stripe_account_id"
    t.datetime "updated_at", null: false
    t.index ["invite_code"], name: "index_teams_on_invite_code", unique: true
    t.index ["stripe_account_id"], name: "index_teams_on_stripe_account_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "account_type"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.string "jti"
    t.string "last_name"
    t.string "manager_verification_status"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "availabilities", "matches"
  add_foreign_key "availabilities", "users"
  add_foreign_key "match_payments", "matches"
  add_foreign_key "match_payments", "users"
  add_foreign_key "matches", "teams"
  add_foreign_key "notifications", "users"
  add_foreign_key "post_reads", "posts"
  add_foreign_key "post_reads", "users"
  add_foreign_key "posts", "teams"
  add_foreign_key "posts", "users"
  add_foreign_key "squad_selections", "matches"
  add_foreign_key "squad_selections", "users"
  add_foreign_key "team_memberships", "teams"
  add_foreign_key "team_memberships", "users"
end
