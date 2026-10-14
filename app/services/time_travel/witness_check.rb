# B03a §"Témoins de vérité": the snapshots frozen by the application are recomputed at the instant they were taken, from the history of the books, and compared with what was
# frozen. A difference means the history cannot be trusted (or the snapshot was changed): it is a blocking anomaly of R19 (C20).
#  - the snapshot of a closing (F10): recomputed at the instant it was taken;
#  - a VAT return that was filed (R09): its grids are computed when it is made, so they are recomputed at the instant it was made.
# Not witnessed yet: the frozen bank reconciliations (R06) and the frozen consolidations (F12), whose figures depend on what the reports do not support yet at an instant.
# => [Divergence]
module TimeTravel::WitnessCheck
  Divergence = Struct.new(:witness_type, :witness_id, :detail, keyword_init: true)

  def self.call(fiscal_year: nil)
    closing_snapshots(fiscal_year) + vat_declarations(fiscal_year)
  end

  def self.closing_snapshots(fiscal_year)
    scope = Accounting::ClosingSnapshot.includes(run: :fiscal_year)
    scope = scope.joins(:run).where(closing_runs: { fiscal_year_id: fiscal_year.id }) if fiscal_year
    scope.filter_map do |snapshot|
      again = Closing::SnapshotContent.call(fiscal_year: snapshot.run.fiscal_year, known_at: snapshot.created_at)
      differences = again.keys.reject { |key| again[key].as_json == snapshot.content[key].as_json }
      next if differences.empty?

      Divergence.new(witness_type: snapshot.class.name, witness_id: snapshot.id, detail: "the history gives another #{differences.join(', ')} at the instant of the snapshot (#{snapshot.created_at.utc.iso8601})")
    end
  end

  def self.vat_declarations(fiscal_year)
    scope = Accounting::VatDeclaration.where.not(status: Accounting::VatDeclaration.statuses[:draft])
    scope = scope.where(fiscal_year_id: fiscal_year.id) if fiscal_year
    scope.filter_map do |declaration|
      grids = Accounting::VatGridQuery.call(fiscal_year_id: declaration.fiscal_year_id, period_start: declaration.period_start, period_end: declaration.period_end, known_at: declaration.created_at)
      again = grids.merge(Accounting::VatGrid.balance(grids)).sort.to_h.transform_values { |v| format("%.2f", v) }
      next if again == declaration.grids.sort.to_h

      Divergence.new(witness_type: declaration.class.name, witness_id: declaration.id,
                     detail: "the history gives other grids (#{(again.keys | declaration.grids.keys).select { |k| again[k] != declaration.grids[k] }.join(', ')}) at the instant the return was made (#{declaration.created_at.utc.iso8601})")
    end
  end
end
