# Step 17 of the closing (F10): the lock and the closing file. The year and its months are locked (F01: the locks the guard of the database enforces), the snapshot
# of the books is taken with its SHA-256, and the closing file (R20, a ZIP of the reports with its manifest of hashes) is made and kept. Done once the three
# stand; refuses while an earlier blocking step is not settled. Idempotent: what exists is not made again.
class Closing::Steps::LockAndBundle < Closing::Step
  self.position = 17
  self.code     = "lock_and_bundle"
  self.title    = "Lock and closing file"
  self.kind     = :action
  self.blocking = true

  def evaluate
    parts = { "locked" => locked?, "snapshot" => run.snapshot.present?, "bundle" => run.bundle.attached? }
    parts.values.all? ? ok(parts) : pending(parts)
  end

  def perform(user:)
    ctx = LightService::Context.make(snapshot: run.snapshot)
    unsettled = earlier_unsettled
    return ctx.tap { |c| c.fail!("These steps are not settled yet: #{unsettled.map { |s| "#{s.position}. #{s.title}" }.join(', ')}.") } if unsettled.any?

    ApplicationRecord.transaction do
      lock_year(user)
      ctx[:snapshot] = take_snapshot
      make_bundle
      Accounting::AuditLog.record!(auditable: run, action: "closing_locked", user: user, payload: { snapshot_sha256: ctx[:snapshot].sha256 })
    end
    ctx
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    ctx.fail!(e.message)
    ctx
  end

  # The reason the locks of this run carry: reopening unlocks those, and only those.
  def lock_reason = "Closing of #{fiscal_year.year} (run #{run.id})"

  private

  def earlier_unsettled
    Closing::Evaluate.call(run: run)
    run.steps.reload.select { |s| s.blocking && s.position < self.class.position && !s.settled? }
  end

  def locked?
    year = Accounting::PeriodLock.in_force.where(kind: :fiscal_year).where("starts_on <= ? AND ends_on >= ?", fiscal_year.start_date, year_end).exists?
    year && months.all? { |from, to| Accounting::PeriodLock.in_force.where(kind: :accounting).where("starts_on <= ? AND ends_on >= ?", from, to).exists? }
  end

  # [[first, last], ...]: each month of the year from its first day, the last one cut at the end of the year.
  def months
    list = []
    from = fiscal_year.start_date
    while from <= year_end
      list << [ from, [ from.end_of_month, year_end ].min ]
      from = from.end_of_month + 1
    end
    list
  end

  def lock_year(user)
    Accounting::PeriodLock.serialize_for_entity!
    unless Accounting::PeriodLock.in_force.where(kind: :fiscal_year).where("starts_on <= ? AND ends_on >= ?", fiscal_year.start_date, year_end).exists?
      Accounting::LockPeriod.call(starts_on: fiscal_year.start_date, ends_on: year_end, kind: :fiscal_year, user: user, reason: lock_reason).tap { |r| raise ArgumentError, r.message if r.failure? }
    end
    months.each do |from, to|
      next if Accounting::PeriodLock.in_force.where(kind: :accounting).where("starts_on <= ? AND ends_on >= ?", from, to).exists?

      Accounting::LockPeriod.call(starts_on: from, ends_on: to, kind: :accounting, user: user, reason: lock_reason).tap { |r| raise ArgumentError, r.message if r.failure? }
    end
  end

  def take_snapshot
    return run.snapshot if run.snapshot

    content = snapshot_content
    Accounting::ClosingSnapshot.create!(run: run, content: content, sha256: Accounting::ClosingSnapshot.fingerprint(content))
  end

  def snapshot_content = Closing::SnapshotContent.call(fiscal_year: fiscal_year)

  def make_bundle
    return if run.bundle.attached?

    result = Accounting::ClosingBundle.call(fiscal_year: fiscal_year)
    run.bundle.attach(io: StringIO.new(result.zip), filename: "closing-#{fiscal_year.year}.zip", content_type: "application/zip")
  end
end
