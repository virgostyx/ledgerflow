# B03a: the reference data as it was at an instant (the versions the database kept): { id => attributes } for the records of `model` that had a version by then. A record
# with none (it did not exist yet, or predates the versions) is absent: the caller keeps what it holds now.
module Accounting::MasterData
  # Shown with the symbols the application uses: the enums of an account come back as their names.
  def self.at(model, ids, time)
    return {} if ids.empty?

    rows = Accounting::MasterDataVersion.where(record_type: model.name, record_id: ids, valid_from: ..time).order(:record_id, id: :desc).select("DISTINCT ON (record_id) record_id, attrs")
    rows.to_h { |row| [ row.record_id, named(model, row.attrs) ] }
  end

  def self.named(model, attrs)
    return attrs unless model == Accounting::Account

    attrs.merge("account_type" => Accounting::Account.account_types.key(attrs["account_type"]), "normal_balance" => Accounting::Account.normal_balances.key(attrs["normal_balance"]))
  end

  # The SQL for the name a partner had at `time`, for a report that reads it in the database (`partner` is the alias of the partners table).
  def self.partner_name_sql(known_at, partner: "p")
    return "#{partner}.name" if known_at.nil? || known_at.current?

    conn = ApplicationRecord.connection
    "COALESCE((SELECT v.attrs->>'name' FROM accounting_master_data_versions v WHERE v.record_type = 'Accounting::Partner' AND v.record_id = #{partner}.id " \
      "AND v.valid_from <= #{conn.quote(known_at.time)} ORDER BY v.id DESC LIMIT 1), #{partner}.name)"
  end
end
