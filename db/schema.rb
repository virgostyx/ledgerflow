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

ActiveRecord::Schema[8.1].define(version: 2026_05_14_211346) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounting_accounts", force: :cascade do |t|
    t.integer "account_class", null: false
    t.integer "account_type", null: false
    t.boolean "active", default: true, null: false
    t.decimal "balance_credit", precision: 15, scale: 2, default: "0.0"
    t.decimal "balance_debit", precision: 15, scale: 2, default: "0.0"
    t.string "code", limit: 10, null: false
    t.datetime "created_at", null: false
    t.boolean "is_leaf", default: true, null: false
    t.string "label_fr", null: false
    t.string "label_nl"
    t.integer "normal_balance", null: false
    t.bigint "parent_id"
    t.boolean "reconcilable", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "vat_code_default"
    t.index ["account_class"], name: "index_accounting_accounts_on_account_class"
    t.index ["active"], name: "index_accounting_accounts_on_active"
    t.index ["code"], name: "index_accounting_accounts_on_code", unique: true
    t.index ["parent_id"], name: "index_accounting_accounts_on_parent_id"
    t.check_constraint "account_class >= 1 AND account_class <= 7", name: "chk_account_class"
  end

  create_table "accounting_audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "auditable_id", null: false
    t.string "auditable_type", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.jsonb "payload", default: {}
    t.datetime "updated_at", null: false
    t.string "user_email"
    t.bigint "user_id"
    t.index ["action"], name: "index_accounting_audit_logs_on_action"
    t.index ["auditable_type", "auditable_id"], name: "index_accounting_audit_logs_on_auditable_type_and_auditable_id"
    t.index ["created_at"], name: "index_accounting_audit_logs_on_created_at"
    t.index ["user_id"], name: "index_accounting_audit_logs_on_user_id"
  end

  create_table "accounting_fiscal_years", force: :cascade do |t|
    t.datetime "closed_at"
    t.bigint "closed_by_id"
    t.datetime "created_at", null: false
    t.date "end_date", null: false
    t.decimal "opening_balance", precision: 15, scale: 2, default: "0.0"
    t.date "start_date", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "year", null: false
    t.index ["status"], name: "idx_accounting_fiscal_years_one_open", unique: true, where: "(status = 0)"
    t.index ["year"], name: "index_accounting_fiscal_years_on_year", unique: true
    t.check_constraint "start_date < end_date", name: "chk_fiscal_year_dates"
  end

  create_table "accounting_journal_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.date "entry_date", null: false
    t.string "external_ref"
    t.bigint "fiscal_year_id", null: false
    t.bigint "journal_id", null: false
    t.datetime "locked_at"
    t.string "locked_by"
    t.integer "project_id"
    t.string "reference", null: false
    t.bigint "reversal_of_id"
    t.bigint "source_id"
    t.string "source_type"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["entry_date"], name: "index_accounting_journal_entries_on_entry_date"
    t.index ["fiscal_year_id"], name: "index_accounting_journal_entries_on_fiscal_year_id"
    t.index ["journal_id"], name: "index_accounting_journal_entries_on_journal_id"
    t.index ["project_id"], name: "index_accounting_journal_entries_on_project_id"
    t.index ["reference"], name: "index_accounting_journal_entries_on_reference", unique: true
    t.index ["source_type", "source_id"], name: "index_accounting_journal_entries_on_source_type_and_source_id"
    t.index ["status"], name: "index_accounting_journal_entries_on_status"
  end

  create_table "accounting_journal_entry_lines", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.decimal "amount_currency", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.decimal "credit", precision: 15, scale: 2, default: "0.0", null: false
    t.string "currency", default: "EUR", null: false
    t.decimal "debit", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "exchange_rate", precision: 10, scale: 6
    t.bigint "journal_entry_id", null: false
    t.string "label"
    t.bigint "partner_id"
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.decimal "vat_amount", precision: 15, scale: 2
    t.integer "vat_code"
    t.index ["account_id"], name: "index_accounting_journal_entry_lines_on_account_id"
    t.index ["journal_entry_id"], name: "index_accounting_journal_entry_lines_on_journal_entry_id"
    t.index ["partner_id"], name: "index_accounting_journal_entry_lines_on_partner_id"
    t.check_constraint "NOT (debit > 0::numeric AND credit > 0::numeric)", name: "chk_not_both_sides"
    t.check_constraint "credit >= 0::numeric", name: "chk_credit_non_negative"
    t.check_constraint "debit > 0::numeric OR credit > 0::numeric", name: "chk_at_least_one_side"
    t.check_constraint "debit >= 0::numeric", name: "chk_debit_non_negative"
  end

  create_table "accounting_journals", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", limit: 5, null: false
    t.datetime "created_at", null: false
    t.integer "current_sequence", default: 0, null: false
    t.bigint "default_account_id"
    t.integer "journal_type", null: false
    t.string "label_fr", null: false
    t.string "sequence_prefix", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_accounting_journals_on_code", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "full_name", default: "", null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "locale", default: "fr", null: false
    t.datetime "locked_at"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 3, null: false
    t.integer "sign_in_count", default: 0, null: false
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "accounting_journal_entries", "accounting_fiscal_years", column: "fiscal_year_id"
  add_foreign_key "accounting_journal_entries", "accounting_journals", column: "journal_id"
  add_foreign_key "accounting_journal_entry_lines", "accounting_accounts", column: "account_id"
  add_foreign_key "accounting_journal_entry_lines", "accounting_journal_entries", column: "journal_entry_id"
end
