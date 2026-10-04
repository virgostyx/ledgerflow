# F04 §7: proposes letterings among the open lines of the current entity, by account and partner, with six rules ranked by
# score. Replaces the proposals still open, keeps those already decided: a rejected group (same lines, same amounts) is not
# proposed again. Lines already partly settled by allocations are left out (they can only be lettered with their group).
class Accounting::SuggestLetterings
  Line = Struct.new(:id, :account_id, :partner_id, :amount, :date, :refs, :invoice_id, :document_type, :credited_invoice_id, keyword_init: true)

  MAX_COMBINATION = 8
  COMBINATION_POOL = 16
  MIN_REF = 4

  def self.call = new.call

  def call
    tolerance = ActsAsTenant.current_tenant.bank_rounding_tolerance
    found = candidate_groups.flat_map { |lines| suggestions_for(lines, tolerance) }
    persist(found.group_by { |s| s[:fingerprint] }.transform_values { |v| v.max_by { |s| s[:score] } }.values)
  end

  private

  def candidate_groups
    open_lines.group_by { |l| [ l.account_id, l.partner_id ] }.values
  end

  # signed: debit - credit, in cents
  def open_lines
    rows = Accounting::JournalEntryLine
      .joins("JOIN accounting_journal_entries e ON e.id = accounting_journal_entry_lines.journal_entry_id")
      .joins("JOIN accounting_accounts a ON a.id = accounting_journal_entry_lines.account_id")
      .joins("LEFT JOIN accounting_invoices i ON i.id = accounting_journal_entry_lines.invoice_id")
      .where(lettering_id: nil, partner_id: Accounting::Partner.select(:id)).not_carried_forward
      .where("e.status IN (?) AND a.reconcilable AND (a.code LIKE '40%' OR a.code LIKE '44%')", Accounting::JournalEntry.ledger_status_values)
      .where("accounting_journal_entry_lines.debit + accounting_journal_entry_lines.credit = accounting_journal_entry_lines.amount_residual")
      .pluck(Arel.sql("accounting_journal_entry_lines.id"), Arel.sql("accounting_journal_entry_lines.account_id"),
             Arel.sql("accounting_journal_entry_lines.partner_id"),
             Arel.sql("((accounting_journal_entry_lines.debit - accounting_journal_entry_lines.credit) * 100)::bigint"),
             Arel.sql("e.entry_date"), Arel.sql("e.id"), Arel.sql("e.reference"),
             Arel.sql("i.id"), Arel.sql("i.invoice_number"), Arel.sql("i.supplier_reference"), Arel.sql("i.payment_reference"),
             Arel.sql("i.document_type"), Arel.sql("i.credited_invoice_id"))
    communications = Accounting::BankTransaction.where(journal_entry_id: rows.map { |r| r[5] }).where.not(structured_communication: nil)
                                                .pluck(:journal_entry_id, :structured_communication).group_by(&:first)
    rows.map do |id, account_id, partner_id, amount, date, entry_id, ref, invoice_id, number, supplier_ref, payment_ref, document_type, credited|
      refs = [ ref, number, supplier_ref, payment_ref, *communications.fetch(entry_id, []).map(&:last) ].filter_map { |r| normalize(r) }
      Line.new(id: id, account_id: account_id, partner_id: partner_id, amount: amount, date: date, refs: refs, invoice_id: invoice_id,
               document_type: document_type, credited_invoice_id: credited)
    end
  end

  def normalize(ref)
    value = ref.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    value if value.length >= MIN_REF
  end

  def suggestions_for(lines, tolerance_euros)
    debits  = lines.select { |l| l.amount.positive? }
    credits = lines.select { |l| l.amount.negative? }
    found = []
    found += reference_pairs(debits, credits)
    found += pairs(debits, credits, 2) { |d, c| exact?(d, c) && same_document?(d, c) }
    found += pairs(debits, credits, 3) { |d, c| exact?(d, c) }
    found += balanced_group(lines)
    paired = found.flat_map { |s| s[:lines].map(&:id) }
    found += combinations(lines.reject { |l| paired.include?(l.id) })
    found += pairs(debits, credits, 6) { |d, c| !exact?(d, c) && (d.amount + c.amount).abs <= (tolerance_euros * 100).to_i }
    found
  end

  def exact?(debit, credit) = debit.amount == -credit.amount

  def same_document?(a, b)
    return false unless a.invoice_id && b.invoice_id
    return true if a.credited_invoice_id == b.invoice_id || b.credited_invoice_id == a.invoice_id

    one_credit_note = [ a, b ].one? { |l| l.document_type == Accounting::Invoice.document_types[:credit_note] }
    one_credit_note && (a.refs & b.refs).any?
  end

  # Candidate pairs by increasing date distance, each line used once.
  def pairs(debits, credits, rule)
    candidates = debits.product(credits).select { |d, c| yield(d, c) }.sort_by { |d, c| [ (d.date - c.date).abs, d.id, c.id ] }
    used = {}
    candidates.filter_map do |d, c|
      next if used[d.id] || used[c.id]

      used[d.id] = used[c.id] = true
      build(rule, [ d, c ])
    end
  end

  # Rule 1 only when no other line could be the partner of either line: anything ambiguous is left to the weaker rules, so a
  # score of 100 is never a guess (it is what the nightly job applies alone). A payment is needed: invoice against credit note is rule 2.
  def reference_pairs(debits, credits)
    candidates = debits.product(credits).select { |d, c| exact?(d, c) && (d.refs & c.refs).any? && !(d.invoice_id && c.invoice_id) }
    candidates.select { |d, c| candidates.count { |x, _| x.id == d.id } == 1 && candidates.count { |_, y| y.id == c.id } == 1 }
              .map { |d, c| build(1, [ d, c ]) }
  end

  def balanced_group(lines)
    return [] unless lines.size > 2 && lines.sum(&:amount).zero?

    [ build(4, lines) ]
  end

  # One line against 2..8 lines of the other sign: smallest combination first, searched in a bounded pool.
  def combinations(lines)
    used = {}
    lines.sort_by(&:id).filter_map do |target|
      next if used[target.id]

      pool = lines.select { |l| l.amount.positive? != target.amount.positive? && !used[l.id] }
                  .sort_by { |l| [ (l.date - target.date).abs, l.id ] }.first(COMBINATION_POOL)
      combo = (2..MAX_COMBINATION).lazy.filter_map { |size| find_combination(pool, target.amount.abs, size) }.first
      next unless combo

      used[target.id] = true
      combo.each { |l| used[l.id] = true }
      build(5, [ target, *combo ])
    end
  end

  def find_combination(pool, total, size, start = 0)
    return (total.zero? ? [] : nil) if size.zero?

    (start...pool.size).each do |i|
      amount = pool[i].amount.abs
      next if amount > total

      rest = find_combination(pool, total - amount, size - 1, i + 1)
      return [ pool[i], *rest ] if rest
    end
    nil
  end

  def build(rule, lines)
    ids = lines.map(&:id).sort
    { rule: rule, score: Accounting::LetteringSuggestion::SCORES.fetch(rule), lines: lines, account_id: lines.first.account_id,
      partner_id: lines.first.partner_id, line_ids: ids,
      fingerprint: Digest::SHA256.hexdigest(lines.sort_by(&:id).map { |l| "#{l.id}:#{l.amount}" }.join("|")) }
  end

  def persist(found)
    Accounting::LetteringSuggestion.transaction do
      connection = ApplicationRecord.connection
      connection.execute("SELECT pg_advisory_xact_lock(hashtext('accounting_lettering_suggestions'), #{ActsAsTenant.current_tenant.id.to_i})")
      known = Accounting::LetteringSuggestion.all.index_by(&:fingerprint)
      current = found.map { |s| s[:fingerprint] }
      known.each_value { |s| s.destroy if s.proposed? && !current.include?(s.fingerprint) }
      found.each do |s|
        existing = known[s[:fingerprint]]
        # accepted, yet its lines are open and no rounding entry waits for them: the draft was deleted, so it can be proposed again
        existing = nil if existing&.accepted? && !Accounting::LetteringWriteOff.pending_for?(existing.line_ids) && existing.destroy
        attrs = s.slice(:rule, :score, :account_id, :partner_id, :line_ids)
        if existing.nil? then Accounting::LetteringSuggestion.create!(**attrs, fingerprint: s[:fingerprint])
        elsif existing.proposed? then existing.update!(attrs)
        end
      end
    end
  end
end
