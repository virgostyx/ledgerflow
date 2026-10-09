require "rails_helper"

# B01a: after any sequence of operations - invoices submitted and changed, decisions of everybody (the right and the wrong people, on the content they saw and on
# a stale one), hand-overs, delegations, time going by - the guarantees of the circuit hold. The seed of a failing sequence is in the message: replay it.
#
#  A. An invoice is approved only by an approval of the content it has now.
#  B. At most one request waits per invoice, and an invoice with one waiting is "to approve".
#  C. A request is approved only when every one of its levels has its approvals (one of them, or all of them).
#  D. Nobody approved what they entered, nor in the name of someone who did (the entity does not allow it).
#  E. Nothing is decided on a request after it was closed.
#  F. An invoice that waits for approval cannot be put in a payment batch.
RSpec.describe "Invariant — approvals hold after random sequences" do
  include_context "with entity"

  SEEDS = (1..12).to_a.freeze
  OPERATIONS = 30

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:account)     { create(:account) }
  let(:people) do
    { owner: create(:user), second_owner: create(:user), accountant: create(:user), second_accountant: create(:user), assistant: create(:user), author: create(:user) }
  end
  let(:suppliers) { create_list(:partner, 4, :supplier) }

  before do
    create(:user_entity, :admin, user: people[:owner], entity: entity)
    create(:user_entity, :admin, user: people[:second_owner], entity: entity)
    create(:user_entity, :accountant, user: people[:accountant], entity: entity)
    create(:user_entity, :accountant, user: people[:second_accountant], entity: entity)
    create(:user_entity, :assistant, user: people[:assistant], entity: entity)
    create(:user_entity, :assistant, user: people[:author], entity: entity)
    entity.update!(step_up_threshold: 1500)
    small = Approvals::Policy.create!(name: "small", subject: :purchase_invoice, priority: 2, conditions: { "max_amount" => "1000" })
    small.steps.create!(position: 1, mode: :any_of, approver_roles: %w[accountant admin], service_hours: 24)
    big = Approvals::Policy.create!(name: "big", subject: :purchase_invoice, priority: 1, conditions: { "min_amount" => "1000.01" })
    big.steps.create!(position: 1, mode: :any_of, approver_roles: %w[accountant admin], service_hours: 24)
    big.steps.create!(position: 2, mode: :all_of, approver_user_ids: [ people[:owner].id, people[:second_owner].id ], service_hours: 24, escalate_to: people[:second_owner])
  end

  def new_invoice(rng)
    invoice = create(:invoice, :supplier, created_by: people.values.sample(random: rng), partner: suppliers.sample(random: rng), fiscal_year: fiscal_year, due_date: Date.current + rng.rand(1..40))
    create(:invoice_line, invoice: invoice, account: account, unit_price: [ 80, 400, 900, 1200, 2500, 4000 ].sample(random: rng))
    invoice.update_columns(status: Accounting::Invoice.statuses[:posted], invoice_number: "ACH-#{SecureRandom.hex(3)}")
    Approvals::Submit.call(invoice: invoice, user: invoice.created_by)
    invoice
  end

  def operation(rng, invoices)
    case rng.rand(10)
    when 0 then invoices << new_invoice(rng)
    when 1..4 then decide_something(rng)
    when 5 then change_something(rng, invoices)
    when 6 then travel(rng.rand(1..60).hours) && Approvals::ProcessDue.call
    when 7 then delegate_something(rng)
    when 8 then Approvals::Submit.call(invoice: invoices.sample(random: rng), user: people.values.sample(random: rng)) if invoices.any?
    else decide_something(rng)
    end
  end

  def decide_something(rng)
    request = Approvals::Request.pending.to_a.sample(random: rng) or return
    user = people.values.sample(random: rng)
    kind = %i[approved approved approved rejected changes_requested transferred].sample(random: rng)
    Approvals::Decide.call(request: request, user: user, decision: kind, comment: ("because" unless kind == :approved), transfer_to_id: people.values.sample(random: rng).id,
                           content_fingerprint: (rng.rand(5).zero? ? "0" * 64 : request.content_fingerprint), recent_second_factor: rng.rand(2).zero?,
                           channel: %i[web mobile api].sample(random: rng))
  end

  def change_something(rng, invoices)
    invoice = invoices.sample(random: rng) or return
    line = Accounting::InvoiceLine.where(invoice_id: invoice.id).first
    case rng.rand(3)
    when 0 then line.update!(unit_price: [ 90, 700, 1900, 3000 ].sample(random: rng)) # significant
    when 1 then invoice.update!(due_date: invoice.due_date + rng.rand(1..9))        # significant
    else invoice.update!(description: "note #{rng.rand(1000)}") && line.update!(description: "label #{rng.rand(1000)}") # cosmetic
    end
  end

  def delegate_something(rng)
    from, to = people.values.sample(2, random: rng)
    Approvals::Delegation.create(delegator: from, delegate: to, starts_on: Date.current - 1, ends_on: Date.current + rng.rand(1..5), reason: "away")
  end

  # => the broken guarantees, as sentences
  def violations(invoices)
    broken = []
    invoices.each do |invoice|
      invoice.reload
      requests = Approvals::Request.where(subject: invoice).includes(:decisions, policy: :steps).to_a
      fingerprint = Approvals::ContentFingerprint.call(invoice)

      if invoice.payment_approved? && requests.none? { |r| r.approved? && r.content_fingerprint == fingerprint }
        broken << "A: invoice #{invoice.id} is approved without an approval of its content"
      end
      pending = requests.select(&:pending?)
      broken << "B: invoice #{invoice.id} has #{pending.size} requests waiting" if pending.size > 1
      broken << "B: invoice #{invoice.id} has a request waiting but is #{invoice.payment_status}" if pending.any? && !invoice.payment_to_approve?
      requests.select(&:approved?).each { |request| broken.concat(approved_without_cause(request).map { |m| "C: #{m}" }) }
      requests.each do |request|
        request.decisions.select(&:approved?).each do |d|
          broken << "D: #{d.approver_id} approved invoice #{invoice.id}, which they or the one they stood in for entered" if [ d.approver_id, d.on_behalf_of_id ].compact.include?(invoice.created_by_id)
        end
        closed_at = request.decided_at
        broken << "E: decisions after the closing of request #{request.id}" if closed_at && request.decisions.any? { |d| d.decided_at > closed_at + 1.second && d.step_position == request.current_step && !request.changes_requested? && !request.invalidated? }
      end
      if invoice.payment_to_approve?
        problems = Payments::Actions::ValidateBatchInvoices.eligibility_problems(invoice)
        broken << "F: invoice #{invoice.id} waits for approval but nothing stops it from being paid" unless problems.any? { |m| m.match?(/waiting for its approval/) }
      end
    end
    broken
  end

  def approved_without_cause(request)
    request.policy.steps.filter_map do |step|
      approvals = request.decisions.select { |d| d.approved? && d.step_position == step.position }
      next "request #{request.id} approved, level #{step.position} has no approval" if approvals.empty?

      if step.all_of?
        covered = approvals.map { |d| d.on_behalf_of_id || d.approver_id }
        missing = step.approver_user_ids - covered
        "request #{request.id} approved, level #{step.position} lacks #{missing.join(', ')}" if missing.any?
      end
    end
  end

  SEEDS.each do |seed|
    it "holds after a sequence of #{OPERATIONS} operations (seed #{seed})" do
      rng = Random.new(seed)
      invoices = []
      invoices << new_invoice(rng)
      OPERATIONS.times do |step|
        operation(rng, invoices)
        broken = violations(invoices)
        expect(broken).to be_empty, "seed #{seed}, operation #{step + 1}: #{broken.first(3).join(' | ')}"
      end
    end
  end
end
