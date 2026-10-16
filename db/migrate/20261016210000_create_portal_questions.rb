# B02c: questions of the firm to the people of the portal, and their answers. What the client reads is in portal_*; the treatments the firm suggests for each choice stay on the firm's side.

class CreatePortalQuestions < ActiveRecord::Migration[8.1]
  def up
    create_table :portal_questions do |t|
      t.string :token, null: false
      t.references :entity, null: false, foreign_key: true
      t.bigint :task_id, null: false # the task of the firm (F08); the portal never follows it
      t.references :portal_user, foreign_key: true # nil: any person who may answer in the company
      t.string :title, null: false
      t.jsonb :context, null: false, default: {} # what the client may see of the thing asked about: a date, a label, an amount, a name
      t.string :answer_type, null: false
      t.jsonb :choices, null: false, default: []
      t.string :status, null: false, default: "open"
      t.date :due_on
      t.datetime :asked_at, null: false
      t.integer :reminders_sent, null: false, default: 0
      t.datetime :last_reminded_at
      t.bigint :asked_by_id, null: false
      t.timestamps
    end
    add_index :portal_questions, :token, unique: true
    add_index :portal_questions, %i[entity_id status]

    create_table :portal_answers do |t|
      t.references :question, null: false, foreign_key: { to_table: :portal_questions }
      t.references :portal_user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.text :body
      t.jsonb :value, null: false, default: {}
      t.datetime :answered_at, null: false
      t.datetime :synced_at # written by the firm's side when the comment of the task is made
      t.timestamps
    end
    add_index :portal_answers, :question_id, unique: true, name: "index_portal_answers_one_per_question"

    create_table :accounting_question_suggestions do |t|
      t.references :entity, null: false, foreign_key: true
      t.bigint :portal_question_id, null: false
      t.string :choice_key, null: false
      t.string :treatment, null: false
      t.timestamps
    end
    add_index :accounting_question_suggestions, %i[portal_question_id choice_key], unique: true, name: "index_question_suggestions_unique"

    add_column :portal_uploads, :question_id, :bigint

    execute <<~SQL
      CREATE OR REPLACE VIEW portal_companies AS
        SELECT id, name, active, COALESCE((features ->> 'b02a')::boolean, false) AS portal_enabled,
               COALESCE((features ->> 'b02a')::boolean, false) AND COALESCE((features ->> 'b02b')::boolean, false) AND COALESCE((features ->> 'f03')::boolean, false) AS upload_enabled,
               portal_show_bank_lines AS show_bank_lines, documents_mail_token,
               COALESCE((features ->> 'b02a')::boolean, false) AND COALESCE((features ->> 'b02c')::boolean, false) AND COALESCE((features ->> 'f08')::boolean, false) AS questions_enabled
        FROM entities
    SQL
  end

  def down
    execute <<~SQL
      DROP VIEW portal_companies;
      CREATE VIEW portal_companies AS
        SELECT id, name, active, COALESCE((features ->> 'b02a')::boolean, false) AS portal_enabled,
               COALESCE((features ->> 'b02a')::boolean, false) AND COALESCE((features ->> 'b02b')::boolean, false) AND COALESCE((features ->> 'f03')::boolean, false) AS upload_enabled,
               portal_show_bank_lines AS show_bank_lines, documents_mail_token
        FROM entities
    SQL
    remove_column :portal_uploads, :question_id
    drop_table :accounting_question_suggestions
    drop_table :portal_answers
    drop_table :portal_questions
  end
end
