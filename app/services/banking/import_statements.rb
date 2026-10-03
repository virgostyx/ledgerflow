# Imports a bank statement file (F02): whole or not at all, never twice, chained and checked.
#
#   Banking::ImportStatements.call(bytes:, user:, source_name:) => ctx
#     success: ctx[:statements], [:imported], [:skipped] (lines), [:warnings], [:batch]
#     failure: ctx[:reason] in :already_imported, :invalid_file (ctx[:errors] = the faulty lines), :unknown_account, :currency_mismatch,
#              :document_refused, :import_failed
#
# Idempotence: a file is known by its SHA-256 (refused with a pointer to the first import); a line by its fingerprint, so a
# statement that overlaps an earlier one only brings its new lines. Imports of one entity are serialised by an advisory lock,
# so two people sending the same file together get one import and one refusal.
# Gaps never refuse a file: the statement that does not add up is marked "to review", a broken chain is shown with its amount.
class Banking::ImportStatements
  PARSER = "coda".freeze
  # What the screens show when no file was chosen.
  NO_FILE = LightService::Context.make(reason: :no_file, errors: [], warnings: []).tap { |ctx| ctx.fail!(I18n.t("banking.import.choose_file")) }.freeze

  def self.call(bytes:, user:, source_name: nil, parser: Banking::Coda::Parser, batch: nil) = new(bytes, user, source_name, parser, batch).call

  # A file with more records than the setting allows (10 000) is imported in the background: judged on its size, 128 characters a record.
  def self.background?(bytes) = bytes.to_s.bytesize / 128 > Rails.configuration.x.bank_import_background_lines

  # The batch is created now (processing), the file kept for the job (it is stored as a document only if the import succeeds).
  def self.enqueue(bytes:, user:, source_name: nil)
    bytes = bytes.to_s.b
    batch = Accounting::ImportBatch.create!(user: user, parser: PARSER, source_name: source_name.to_s.presence || "statement.cod", file_sha256: Digest::SHA256.hexdigest(bytes), result: "processing")
    batch.queued_file.attach(io: StringIO.new(bytes), filename: "#{batch.source_name}.queued", content_type: "application/octet-stream")
    Banking::ImportStatementsJob.perform_later(batch.id, ActsAsTenant.current_tenant.id)
    batch
  end

  # How far a background import is: { done:, total: } while it runs (nil when unknown).
  def self.progress(batch) = Rails.cache.read(progress_key(batch))
  def self.progress_key(batch) = "bank_import_progress:#{batch.id}"

  def initialize(bytes, user, source_name, parser, batch = nil)
    @bytes = bytes.to_s.b
    @user = user
    @source_name = source_name.to_s.presence || "statement.cod"
    @parser = parser
    @queued = batch
    @sha256 = Digest::SHA256.hexdigest(@bytes)
    @created = []
    @ctx = LightService::Context.make(statements: [], imported: 0, skipped: 0, warnings: [], errors: [], batch: nil, reason: nil,
                                      drafted: 0, suggested: 0)
  end

  def call
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(hashtext('bank_statement_import'), #{ActsAsTenant.current_tenant.id})")
      import
      raise ActiveRecord::Rollback if @ctx.failure?
    end
    remember_refusal if @ctx.failure? && (@ctx[:reason] != :already_imported || @queued) # a queued batch must leave "processing"
    link_source_file && match_lines if @ctx.success?
    @ctx
  rescue ActiveRecord::ActiveRecordError => e
    refuse(:import_failed, I18n.t("banking.import.failed", detail: e.message.truncate(200)))
    remember_refusal
    @ctx
  end

  private

  def import
    return unless (already = Accounting::ImportBatch.imported.find_by(file_sha256: @sha256)).nil? || refuse_known(already)

    result = @parser.call(@bytes)
    return refuse(:invalid_file, I18n.t("banking.import.invalid_file", count: result.errors.size), errors: result.errors) unless result.success?

    accounts = resolve_accounts(result.statements) or return
    document = store_file or return
    batch = if @queued
      @queued.tap { |queued| queued.update!(result: "imported", document: document) }
    else
      Accounting::ImportBatch.create!(user: @user, parser: PARSER, source_name: @source_name, file_sha256: @sha256, result: "imported", document: document)
    end
    @ctx[:batch] = batch
    @ctx[:warnings].concat(result.warnings)
    seen = Hash.new(0)
    @total = result.statements.sum { |statement| statement.lines.size }
    @done = 0
    result.statements.each_with_index { |parsed, i| import_statement(batch, parsed, accounts[i], seen) }
    accounts.uniq.each { |account| Banking::RechainStatements.call(bank_account: account).each { |message| @ctx[:warnings] << message } }
    batch.update!(statements_count: result.statements.size, lines_read: @ctx[:imported] + @ctx[:skipped], lines_imported: @ctx[:imported], lines_skipped: @ctx[:skipped],
                  warnings_list: @ctx[:warnings])
    audit(batch)
  end

  # In the background, how far the lines are (every 100, and at the end), for the screen. The cache is outside the import's transaction.
  def report_progress
    @done += 1
    return unless @queued && (@done % 100).zero? || @queued && @done == @total

    Rails.cache.write(self.class.progress_key(@queued), { done: @done, total: @total }, expires_in: 1.day)
  end

  # The source file belongs to the statements it brought: it leaves the document inbox. After the commit, on a fresh instance: Rails
  # runs the after-commit of only the last instance of a record saved in a transaction, and the file is uploaded by the first.
  def link_source_file
    @ctx[:statements].each do |statement|
      linked = Accounting::LinkDocument.call(document: Accounting::Document.find(@ctx[:batch].document_id), target: statement, user: @user)
      @ctx[:warnings] << linked.message if linked.failure?
    end
    true
  end

  # The engine runs on what came in (F02). It never undoes the import: what it cannot book is reported as a warning.
  def match_lines
    matched = Banking::AutoMatch.call(transactions: @created)
    @ctx[:drafted] = matched[:drafted]
    @ctx[:suggested] = matched[:suggested]
    @ctx[:warnings].concat(matched[:problems].map { |problem| I18n.t("banking.import.match_problem", detail: problem) })
  rescue StandardError => e
    @ctx[:warnings] << I18n.t("banking.import.match_problem", detail: e.message)
  end

  def refuse_known(batch)
    refuse(:already_imported, I18n.t("banking.import.already_imported", date: I18n.l(batch.created_at.to_date), who: batch.user&.email || "-"))
    false
  end

  def refuse(reason, message, **extra)
    @ctx[:reason] = reason
    extra.each { |key, value| @ctx[key] = value }
    @ctx.fail!(message)
    false
  end

  # Every account of the file must be a bank account of the entity, in the currency of the statement.
  def resolve_accounts(parsed)
    accounts = parsed.map { |statement| Accounting::BankAccount.find_by(iban: statement.iban || statement.account_number) }
    unknown = parsed.each_index.select { |i| accounts[i].nil? }.map { |i| mask(parsed[i].iban || parsed[i].account_number) }
    return refuse(:unknown_account, I18n.t("banking.import.unknown_account", accounts: unknown.uniq.join(", "))) && nil if unknown.any?

    parsed.each_index do |i|
      next if parsed[i].currency.blank? || parsed[i].currency == accounts[i].currency

      return refuse(:currency_mismatch, I18n.t("banking.import.currency_mismatch", account: mask(accounts[i].iban), statement: parsed[i].currency, bank_account: accounts[i].currency)) && nil
    end
    accounts
  end

  # The source file goes to the document store (F03). The same file already there (uploaded by hand) is reused.
  def store_file
    uploaded = Accounting::UploadDocument.call(io: StringIO.new(@bytes), filename: @source_name, user: @user, origin: :bank_import, kind: :statement)
    return uploaded[:document] if uploaded.success?
    return uploaded[:existing] if uploaded[:reason] == :duplicate && uploaded[:existing]

    refuse(:document_refused, uploaded.message)
    nil
  end

  def import_statement(batch, parsed, account, seen)
    statement = Accounting::BankStatement.create!(
      bank_account: account, import_batch: batch, sequence: parsed.sequence, old_balance: parsed.old_balance, old_balance_date: parsed.old_balance_date,
      new_balance: parsed.new_balance, new_balance_date: parsed.new_balance_date, integrity_gap: parsed.integrity_gap,
      status: parsed.integrity_ok? ? "ok" : "to_review", messages: parsed.messages, header: parsed.header.transform_values { |v| v.is_a?(Date) ? v.iso8601 : v }
    )
    warn_integrity(parsed, account)
    import_lines(statement, parsed, account, seen)
  end

  def warn_integrity(parsed, account)
    return if parsed.integrity_ok?

    @ctx[:warnings] << I18n.t("banking.import.does_not_add_up", account: mask(account.iban), sequence: parsed.sequence, gap: parsed.integrity_gap.to_s("F"))
  end

  def import_lines(statement, parsed, account, seen)
    prints = parsed.lines.map { |line| fingerprint_of(account, line, seen) }
    known = account.transactions.where(fingerprint: prints).pluck(:fingerprint).to_set
    parsed.lines.zip(prints).each do |line, print|
      if known.include?(print)
        @ctx[:skipped] += 1
      else
        @created << Accounting::BankTransaction.create!(attributes_for(statement, account, line, print))
        @ctx[:imported] += 1
      end
      report_progress
    end
    @ctx[:statements] << statement
  end

  # Two identical lines of one file are two movements: the nth one carries its rank, so that a later file repeating them matches
  # them one for one.
  def fingerprint_of(account, line, seen)
    base = line.fingerprint
    seen[[ account.id, base ]] += 1
    rank = seen[[ account.id, base ]]
    rank == 1 ? base : "#{base}##{rank}"
  end

  def attributes_for(statement, account, line, print)
    { bank_account: account, statement: statement, transaction_date: line.entry_date || line.value_date, value_date: line.value_date, amount: line.amount,
      currency: account.currency, description: description_of(line), reference: nil, status: :pending,
      counterparty_name: line.counterparty_name, counterparty_iban: line.counterparty_iban, structured_communication: line.structured_communication,
      bank_reference: line.bank_reference.presence, transaction_code: line.transaction.values.join, fingerprint: print,
      raw_data: { records: line.raw, details: line.details.map(&:raw), information: line.information, transaction: line.transaction,
                  customer_reference: line.customer_reference, r_type: line.r_type, iso_reason: line.iso_reason } }
  end

  def description_of(line)
    shown = Accounting::StructuredCommunication.display(line.structured_communication) if line.structured_type.in?(%w[101 102]) && line.structured_communication.to_s.match?(/\A\d{12}\z/)
    [ shown, line.communication.presence ].compact.join(" ").presence || line.information.join(" ").presence || line.counterparty_name
  end

  def audit(batch)
    Accounting::AuditLog.record!(
      auditable: batch, action: "bank_statement_import", user: @user,
      payload: { file_sha256: @sha256, source_name: @source_name, parser: PARSER, statements: batch.statements_count, lines_read: batch.lines_read,
                 lines_imported: batch.lines_imported, lines_skipped: batch.lines_skipped, accounts: @ctx[:statements].map { |s| mask(s.bank_account.iban) }.uniq,
                 warnings: @ctx[:warnings].size }
    )
  end

  # The file is kept out of the transaction that failed: a refusal leaves its batch, with what was wrong.
  def remember_refusal
    list = Array(@ctx[:errors]).map { |e| e.respond_to?(:line) ? { line: e.line, text: e.text } : e.to_s }
    list = [ { text: @ctx.message } ] if list.empty?
    return @queued.update!(result: "rejected", errors_list: list) if @queued

    Accounting::ImportBatch.create!(user: @user, parser: PARSER, source_name: @source_name, file_sha256: @sha256, result: "rejected", errors_list: list)
  end

  def mask(iban)
    iban = iban.to_s
    iban.length > 8 ? "#{iban[0, 4]}#{'*' * (iban.length - 8)}#{iban.last(4)}" : iban
  end
end
