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

ActiveRecord::Schema[8.1].define(version: 2026_08_23_202508) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

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

  create_table "developer_account_actions", force: :cascade do |t|
    t.string "action_type", null: false
    t.datetime "created_at", null: false
    t.bigint "developer_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "notes", null: false
    t.bigint "target_user_id", null: false
    t.datetime "updated_at", null: false
    t.index ["action_type"], name: "index_developer_account_actions_on_action_type"
    t.index ["developer_id"], name: "index_developer_account_actions_on_developer_id"
    t.index ["target_user_id"], name: "index_developer_account_actions_on_target_user_id"
  end

  create_table "developers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "jti", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_developers_on_email", unique: true
    t.index ["jti"], name: "index_developers_on_jti", unique: true
    t.index ["reset_password_token"], name: "index_developers_on_reset_password_token", unique: true
  end

  create_table "legal_acceptances", force: :cascade do |t|
    t.datetime "accepted_at", null: false
    t.datetime "created_at", null: false
    t.string "document_type", null: false
    t.string "document_version", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "document_type", "document_version"], name: "index_legal_acceptances_unique", unique: true
    t.index ["user_id"], name: "index_legal_acceptances_on_user_id"
  end

  create_table "match_awards", force: :cascade do |t|
    t.decimal "average_rating", precision: 3, scale: 1, null: false
    t.string "award_type", null: false
    t.datetime "awarded_at", null: false
    t.datetime "created_at", null: false
    t.bigint "match_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["match_id", "user_id", "award_type"], name: "index_match_awards_unique", unique: true
    t.index ["match_id"], name: "index_match_awards_on_match_id"
    t.index ["user_id"], name: "index_match_awards_on_user_id"
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

  create_table "match_player_stats", force: :cascade do |t|
    t.integer "assists", default: 0, null: false
    t.boolean "clean_sheet", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "goals", default: 0, null: false
    t.bigint "match_id", null: false
    t.bigint "player_id", null: false
    t.integer "red_cards", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "yellow_cards", default: 0, null: false
    t.index ["match_id", "player_id"], name: "index_match_player_stats_unique", unique: true
    t.index ["match_id"], name: "index_match_player_stats_on_match_id"
    t.index ["player_id"], name: "index_match_player_stats_on_player_id"
    t.check_constraint "assists >= 0", name: "match_player_stats_assists_non_negative"
    t.check_constraint "goals >= 0", name: "match_player_stats_goals_non_negative"
    t.check_constraint "red_cards >= 0 AND red_cards <= 1", name: "match_player_stats_red_cards_range"
    t.check_constraint "yellow_cards >= 0 AND yellow_cards <= 2", name: "match_player_stats_yellow_cards_range"
  end

  create_table "match_ratings", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.bigint "match_id", null: false
    t.bigint "player_id", null: false
    t.bigint "rater_id", null: false
    t.decimal "rating", precision: 3, scale: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["match_id", "rater_id", "player_id"], name: "index_match_ratings_unique", unique: true
    t.index ["match_id"], name: "index_match_ratings_on_match_id"
    t.index ["player_id"], name: "index_match_ratings_on_player_id"
    t.index ["rater_id"], name: "index_match_ratings_on_rater_id"
    t.check_constraint "rater_id <> player_id", name: "match_ratings_no_self_rating"
    t.check_constraint "rating >= 1.0 AND rating <= 10.0", name: "match_ratings_rating_range"
  end

  create_table "matches", force: :cascade do |t|
    t.datetime "availability_reminder_sent_at"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "formation"
    t.datetime "kickoff_time"
    t.decimal "latitude", precision: 10, scale: 6
    t.string "location"
    t.decimal "longitude", precision: 10, scale: 6
    t.string "match_type"
    t.string "opponent"
    t.integer "opponent_score"
    t.datetime "ratings_finalised_at"
    t.bigint "team_id", null: false
    t.integer "team_score"
    t.datetime "updated_at", null: false
    t.index ["cancelled_at"], name: "index_matches_on_cancelled_at"
    t.index ["team_id"], name: "index_matches_on_team_id"
    t.check_constraint "opponent_score >= 0", name: "matches_opponent_score_non_negative"
    t.check_constraint "team_score >= 0", name: "matches_team_score_non_negative"
  end

  create_table "moderation_actions", force: :cascade do |t|
    t.string "action_type", null: false
    t.datetime "created_at", null: false
    t.bigint "developer_id"
    t.jsonb "metadata", default: {}, null: false
    t.text "notes"
    t.bigint "report_id", null: false
    t.bigint "target_user_id"
    t.datetime "updated_at", null: false
    t.index ["developer_id"], name: "index_moderation_actions_on_developer_id"
    t.index ["report_id", "created_at"], name: "index_moderation_actions_on_report_id_and_created_at"
    t.index ["report_id"], name: "index_moderation_actions_on_report_id"
    t.index ["target_user_id"], name: "index_moderation_actions_on_target_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.string "deduplication_key"
    t.bigint "featured_user_id"
    t.datetime "kept_at"
    t.bigint "match_id"
    t.bigint "match_payment_id"
    t.text "message"
    t.string "notification_type"
    t.datetime "opened_at"
    t.bigint "post_id"
    t.boolean "read", default: false, null: false
    t.bigint "team_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["actor_id"], name: "index_notifications_on_actor_id"
    t.index ["featured_user_id"], name: "index_notifications_on_featured_user_id"
    t.index ["match_id"], name: "index_notifications_on_match_id"
    t.index ["match_payment_id"], name: "index_notifications_on_match_payment_id"
    t.index ["post_id"], name: "index_notifications_on_post_id"
    t.index ["team_id"], name: "index_notifications_on_team_id"
    t.index ["user_id", "deduplication_key"], name: "index_notifications_on_user_and_deduplication_key", unique: true, where: "(deduplication_key IS NOT NULL)"
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

  create_table "push_devices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "platform", null: false
    t.text "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token"], name: "index_push_devices_on_token", unique: true
    t.index ["user_id"], name: "index_push_devices_on_user_id"
  end

  create_table "reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "details"
    t.text "moderation_notes"
    t.string "reason", null: false
    t.bigint "reportable_id"
    t.string "reportable_type"
    t.bigint "reported_user_id"
    t.bigint "reporter_id", null: false
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["reportable_type", "reportable_id"], name: "index_reports_on_reportable"
    t.index ["reported_user_id"], name: "index_reports_on_reported_user_id"
    t.index ["reporter_id"], name: "index_reports_on_reporter_id"
    t.index ["reviewed_by_id"], name: "index_reports_on_reviewed_by_id"
    t.index ["status", "created_at"], name: "index_reports_on_status_and_created_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "squad_selections", force: :cascade do |t|
    t.boolean "captain", default: false, null: false
    t.datetime "created_at", null: false
    t.boolean "is_freekick_taker", default: false, null: false
    t.boolean "is_left_corner_taker", default: false, null: false
    t.boolean "is_penalty_taker", default: false, null: false
    t.boolean "is_right_corner_taker", default: false, null: false
    t.bigint "match_id", null: false
    t.string "position"
    t.string "selection_type"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["match_id", "user_id"], name: "index_squad_selections_on_match_id_and_user_id", unique: true
    t.index ["match_id"], name: "index_squad_selections_on_match_id"
    t.index ["user_id"], name: "index_squad_selections_on_user_id"
  end

  create_table "store_subscription_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "environment", null: false
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at"
    t.datetime "processed_at"
    t.text "processing_error"
    t.string "processing_status", default: "pending", null: false
    t.string "provider", null: false
    t.string "provider_event_id", null: false
    t.string "provider_subscription_id"
    t.bigint "team_id"
    t.datetime "updated_at", null: false
    t.datetime "verification_checked_at"
    t.text "verification_error"
    t.string "verification_status", default: "pending", null: false
    t.index ["processing_status", "created_at"], name: "idx_store_events_processing_status"
    t.index ["provider", "provider_event_id"], name: "idx_store_events_provider_event", unique: true
    t.index ["provider", "provider_subscription_id"], name: "idx_store_events_provider_subscription"
    t.index ["team_id"], name: "index_store_subscription_events_on_team_id"
    t.index ["verification_status", "created_at"], name: "idx_store_events_verification_status"
  end

  create_table "team_entitlements", force: :cascade do |t|
    t.boolean "auto_renews", default: false, null: false
    t.string "billing_period"
    t.datetime "created_at", null: false
    t.datetime "ends_at"
    t.string "plan", null: false
    t.string "provider"
    t.string "provider_base_plan_id"
    t.string "provider_product_id"
    t.string "provider_subscription_id"
    t.string "source", null: false
    t.datetime "starts_at", null: false
    t.string "status", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_subscription_id"], name: "index_team_entitlements_on_provider_subscription_id", unique: true, where: "(provider_subscription_id IS NOT NULL)"
    t.index ["team_id"], name: "index_team_entitlements_on_team_id", unique: true
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

  create_table "training_availabilities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "status", null: false
    t.bigint "training_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["training_id", "user_id"], name: "index_training_availabilities_on_training_id_and_user_id", unique: true
    t.index ["training_id"], name: "index_training_availabilities_on_training_id"
    t.index ["user_id"], name: "index_training_availabilities_on_user_id"
  end

  create_table "trainings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "latitude", precision: 10, scale: 6
    t.string "location", null: false
    t.decimal "longitude", precision: 10, scale: 6
    t.datetime "meet_time", null: false
    t.datetime "starts_at", null: false
    t.bigint "team_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "starts_at"], name: "index_trainings_on_team_id_and_starts_at"
    t.index ["team_id"], name: "index_trainings_on_team_id"
  end

  create_table "user_blocks", force: :cascade do |t|
    t.bigint "blocked_user_id", null: false
    t.bigint "blocker_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_user_id"], name: "index_user_blocks_on_blocked_user_id"
    t.index ["blocker_id", "blocked_user_id"], name: "index_user_blocks_on_blocker_id_and_blocked_user_id", unique: true
    t.index ["blocker_id"], name: "index_user_blocks_on_blocker_id"
    t.check_constraint "blocker_id <> blocked_user_id", name: "user_blocks_cannot_block_self"
  end

  create_table "users", force: :cascade do |t|
    t.string "account_type"
    t.datetime "banned_at"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.string "jti"
    t.string "last_name"
    t.string "manager_verification_status"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "suspended_at"
    t.text "suspension_reason"
    t.datetime "updated_at", null: false
    t.index ["banned_at"], name: "index_users_on_banned_at"
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["suspended_at"], name: "index_users_on_suspended_at"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "availabilities", "matches"
  add_foreign_key "availabilities", "users"
  add_foreign_key "developer_account_actions", "developers"
  add_foreign_key "developer_account_actions", "users", column: "target_user_id"
  add_foreign_key "legal_acceptances", "users"
  add_foreign_key "match_awards", "matches"
  add_foreign_key "match_awards", "users"
  add_foreign_key "match_payments", "matches"
  add_foreign_key "match_payments", "users"
  add_foreign_key "match_player_stats", "matches"
  add_foreign_key "match_player_stats", "users", column: "player_id"
  add_foreign_key "match_ratings", "matches"
  add_foreign_key "match_ratings", "users", column: "player_id"
  add_foreign_key "match_ratings", "users", column: "rater_id"
  add_foreign_key "matches", "teams"
  add_foreign_key "moderation_actions", "developers"
  add_foreign_key "moderation_actions", "reports"
  add_foreign_key "moderation_actions", "users", column: "target_user_id"
  add_foreign_key "notifications", "match_payments"
  add_foreign_key "notifications", "matches"
  add_foreign_key "notifications", "posts"
  add_foreign_key "notifications", "teams"
  add_foreign_key "notifications", "users"
  add_foreign_key "notifications", "users", column: "actor_id"
  add_foreign_key "notifications", "users", column: "featured_user_id"
  add_foreign_key "post_reads", "posts"
  add_foreign_key "post_reads", "users"
  add_foreign_key "posts", "teams"
  add_foreign_key "posts", "users"
  add_foreign_key "push_devices", "users"
  add_foreign_key "reports", "developers", column: "reviewed_by_id"
  add_foreign_key "reports", "users", column: "reported_user_id"
  add_foreign_key "reports", "users", column: "reporter_id"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "squad_selections", "matches"
  add_foreign_key "squad_selections", "users"
  add_foreign_key "store_subscription_events", "teams"
  add_foreign_key "team_entitlements", "teams"
  add_foreign_key "team_memberships", "teams"
  add_foreign_key "team_memberships", "users"
  add_foreign_key "training_availabilities", "trainings"
  add_foreign_key "training_availabilities", "users"
  add_foreign_key "trainings", "teams"
  add_foreign_key "user_blocks", "users", column: "blocked_user_id"
  add_foreign_key "user_blocks", "users", column: "blocker_id"
end
