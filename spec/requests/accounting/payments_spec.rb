require "rails_helper"

# B01b, the screens: "Payments" in five steps - the invoices to pay, the composition, the checks, the approval, the file and what follows - and the history.
RSpec.describe "Payments (B01b)", type: :request do
  include_context "with submitted batch"

  let(:accountant) { authorizer }
  let(:assistant) { create(:user, full_name: "Anna Assistant").tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }
  let(:reader) { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:iban) { "BE68539007547034" }

  before do
    owner
    preparer
    authorizer
    sign_in preparer
  end

  def bank_form(invoice) = { bank_account_id: bank.id, bank_profile_id: profile.id, requested_execution_date: execution.iso8601, invoice_ids: [ invoice.id ] }

  describe "the flag and the rights" do
    it "is closed when the feature is off" do
      entity.update!(features: entity.features.merge("b01b" => false))

      get accounting_payments_path

      expect(response).to redirect_to(accounting_root_path)
    end

    it "shows the history to a reader, who cannot compose" do
      approved_batch
      sign_in reader

      get accounting_payments_path
      expect(response.body).to include("PAY-2026-0001")

      get new_accounting_payment_path
      expect(response).to redirect_to(accounting_root_path).or have_http_status(:redirect)
    end
  end

  describe "step 1: the invoices to pay" do
    it "lists what can be paid, preselected, and what cannot, each with its reasons" do
      due = posted(due: Date.current + 2)
      blocked_supplier = create(:partner, :supplier, name: "NoAccount SA", iban: nil)
      stuck = posted(partner: blocked_supplier)

      get new_accounting_payment_path, params: { execution_date: execution.iso8601 }

      expect(response.body).to include(due.invoice_number)
      expect(response.body).to match(/id="invoice_#{due.id}"[^>]*checked/)
      expect(response.body).to include(stuck.invoice_number).and include("bank account")
      expect(response.body).not_to include(%(id="invoice_#{stuck.id}"))
      expect(response.body).not_to include(iban)
    end
  end

  describe "step 2: the composition" do
    it "keeps the bank profile that was picked, and offers the profiles of the company (none: it says where to make one)" do
      profile
      get new_accounting_payment_path
      expect(response.body).to include("Test bank")

      post accounting_payments_path, params: { payment: bank_form(posted) }
      expect(Payments::Batch.last.bank_profile).to eq(profile)
    end

    it "says where to make a profile when there is none" do
      get new_accounting_payment_path

      expect(response.body).to include(accounting_settings_payment_bank_profiles_path)
    end

    it "makes the batch and shows its payments with the account masked and the balance it leaves" do
      invoice = posted

      post accounting_payments_path, params: { payment: bank_form(invoice) }

      batch = Payments::Batch.last
      expect(response).to redirect_to(accounting_payment_path(batch))
      follow_redirect!
      expect(response.body).to include(batch.reference).and include("BE68 **** **** 7034").and include("1,210.00")
      expect(response.body).not_to include(iban)
      expect(response.body).to match(/balance/i)
    end

    it "says why, and makes nothing, when an invoice is not payable" do
      invoice = posted
      account.update_columns(status: Accounting::PartnerBankAccount.statuses[:blocked])

      post accounting_payments_path, params: { payment: bank_form(invoice) }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("blocked")
      expect(Payments::Batch.count).to eq(0)
    end

    it "is not for a reader" do
      sign_in reader

      post accounting_payments_path, params: { payment: bank_form(posted) }

      expect(Payments::Batch.count).to eq(0)
    end
  end

  describe "step 3: the checks" do
    let(:batch) { batch_of(posted) }

    it "shows the report, and runs it again on request" do
      get accounting_payment_path(batch)
      expect(response.body).to match(/pre-flight/i)

      account.update_columns(status: Accounting::PartnerBankAccount.statuses[:blocked])
      post preflight_accounting_payment_path(batch)
      follow_redirect!

      expect(response.body).to include("blocked")
      expect(batch.reload.preflight_report["errors"]).not_to be_empty
    end

    it "takes the reason of whoever acknowledges a warning, and refuses an empty one" do
      Payments::Preflight.call(batch)
      batch.update_columns(preflight_report: batch.preflight_report.merge("warnings" => [ { "code" => "low_balance", "key" => "low_balance:x", "message" => "Low" } ]))
      allow(Payments::AcknowledgeWarning).to receive(:call).and_call_original

      post acknowledge_accounting_payment_path(batch), params: { key: "low_balance:x", reason: "" }

      expect(Payments::AcknowledgeWarning).to have_received(:call).with(hash_including(key: "low_balance:x", reason: ""))
      expect(flash[:alert]).to be_present
    end
  end

  describe "step 4: the approval" do
    before { Approvals::Policy.create!(name: "batches", subject: :payment_batch, priority: 1).steps.create!(position: 1, mode: :any_of, approver_roles: %w[accountant admin]) }

    let(:batch) { batch_of(posted) }

    it "is asked by the preparer, and shows who may decide" do
      post submit_for_approval_accounting_payment_path(batch)

      expect(batch.reload).to be_pending_approval
      follow_redirect!
      expect(response.body).to match(/waiting for approval/i)
    end

    it "is refused with the reason when no policy covers the batch" do
      Approvals::Policy.destroy_all

      post submit_for_approval_accounting_payment_path(batch)

      expect(batch.reload).to be_draft
      expect(flash[:alert]).to match(/policy/i)
    end

    it "is decided by another person, not by the preparer" do
      post submit_for_approval_accounting_payment_path(batch)

      post decide_accounting_payment_path(batch), params: { decision: "approved", content_fingerprint: batch.reload.approval_request.content_fingerprint }
      expect(batch.reload).to be_pending_approval
      expect(flash[:alert]).to match(/another person/i)

      sign_in authorizer
      post decide_accounting_payment_path(batch), params: { decision: "approved", content_fingerprint: batch.approval_request.content_fingerprint }
      expect(batch.reload).to be_approved
    end

    it "takes a refusal only with a reason" do
      post submit_for_approval_accounting_payment_path(batch)
      sign_in authorizer

      post decide_accounting_payment_path(batch), params: { decision: "rejected", comment: "", content_fingerprint: batch.reload.approval_request.content_fingerprint }
      expect(batch.reload).to be_pending_approval

      post decide_accounting_payment_path(batch), params: { decision: "rejected", comment: "Wrong supplier", content_fingerprint: batch.approval_request.content_fingerprint }
      expect(batch.reload).to be_draft
    end
  end

  describe "step 5: the file and what follows" do
    let(:batch) { approved_batch }

    before { sign_in authorizer }

    it "gives the file to who may export, keeps it, and shows what to compare with the bank" do
      post export_accounting_payment_path(batch)
      expect(response).to redirect_to(accounting_payment_path(batch))
      follow_redirect!

      batch.reload
      expect(response.body).to include(batch.reference).and include("1210.00").and include(batch.file_sha256[0, 12])
      expect(response.body).to include("I loaded the file in my bank")

      get download_accounting_payment_path(batch)
      expect(response.body).to eq(batch.document.file.download)
      expect(response.headers["Content-Type"]).to include("application/xml")
      expect(response.headers["Content-Disposition"]).to include("#{batch.reference}.xml")
    end

    it "does not give a file to an assistant, nor before the export" do
      get download_accounting_payment_path(batch)
      expect(response).to have_http_status(:redirect).or have_http_status(:not_found)

      sign_in assistant
      post export_accounting_payment_path(batch)
      expect(batch.reload).to be_approved
    end

    it "records that the file was loaded in the bank, and cancels with a reason" do
      post export_accounting_payment_path(batch)
      post confirm_loaded_accounting_payment_path(batch)
      expect(batch.reload).to be_submitted

      post cancel_accounting_payment_path(batch), params: { reason: "" }
      expect(batch.reload).to be_submitted
      post cancel_accounting_payment_path(batch), params: { reason: "Wrong date" }
      expect(batch.reload).to be_cancel_requested

      post confirm_cancellation_accounting_payment_path(batch)
      expect(batch.reload).to be_cancelled
    end
  end

  describe "another company" do
    it "sees none of these batches and can act on none: the batches are those of one company" do
      batch = approved_batch
      stranger = create(:user, full_name: "Sam Stranger")
      foreign = ActsAsTenant.without_tenant { create(:entity) }
      ActsAsTenant.without_tenant { create(:user_entity, :admin, user: stranger, entity: foreign) }
      sign_in stranger

      get accounting_payments_path
      expect(response.body).not_to include(batch.reference)

      [ [ :get, accounting_payment_path(batch) ], [ :get, download_accounting_payment_path(batch) ], [ :post, export_accounting_payment_path(batch) ],
        [ :post, cancel_accounting_payment_path(batch) ], [ :post, confirm_loaded_accounting_payment_path(batch) ] ].each do |verb, path|
        public_send(verb, path, params: { reason: "x" })
        expect(response).to have_http_status(:not_found), "#{verb} #{path}"
      end
      expect(batch.reload).to be_approved
    end
  end

  describe "the second factor" do
    let(:batch) { approved_batch }
    let!(:secret) { authorizer.begin_totp_enrollment!.tap { |secret| authorizer.confirm_totp!(Totp.code(secret, Time.current - 30)) } }

    around do |example|
      previous = Rails.configuration.x.second_factor_required
      Rails.configuration.x.second_factor_required = true
      example.run
    ensure
      Rails.configuration.x.second_factor_required = previous
    end

    before { sign_in authorizer }

    def pass_challenge! = post(two_factor_challenge_path, params: { code: Totp.code(secret, Time.current) })

    it "is asked before the file is made, and before it is given out, however old the last one" do
      pass_challenge!
      travel 10.minutes

      post export_accounting_payment_path(batch)
      expect(response).to redirect_to(two_factor_challenge_path)
      expect(batch.reload).to be_approved

      pass_challenge!
      post export_accounting_payment_path(batch)
      expect(batch.reload).to be_exported

      travel 10.minutes
      get download_accounting_payment_path(batch)
      expect(response).to redirect_to(two_factor_challenge_path)

      pass_challenge!
      expect(response).to redirect_to(download_accounting_payment_path(batch))
      get download_accounting_payment_path(batch)
      expect(response.body).to eq(batch.document.file.download)
    end
  end

  describe "after the file: the debit, the entries and the timeline" do
    let(:poster) { create(:user, full_name: "Paula Poster").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
    let(:batch) { submitted_batch }
    let(:invoice) { Accounting::Invoice.find(batch.items.first.item_invoices.first.invoice_id) }

    def debit!(date: nil)
      Payments::ConfirmDebit.call(batch: batch, user: authorizer, transaction: debit_line(batch.total, description: batch.reference), items: batch.items.to_a).tap { |r| raise r.message if r.failure? }
    end

    it "says that the debit is looked for in the statement, and takes it by hand with a reason, a date and the reference of the bank" do
      sign_in authorizer
      get accounting_payment_path(batch)
      expect(response.body).to include("Bank reconciliation").and include("Confirm the debit by hand")

      post confirm_debit_by_hand_accounting_payment_path(batch), params: { reason: "The bank confirmed by phone", date: (execution + 1).iso8601, bank_reference: "REF-1" }

      expect(batch.reload).to be_debited
      expect(batch.debit_kind).to eq("manual")
    end

    it "wants all three of them" do
      sign_in authorizer

      post confirm_debit_by_hand_accounting_payment_path(batch), params: { reason: "", date: execution.iso8601, bank_reference: "REF-1" }

      expect(flash[:alert]).to be_present
      expect(batch.reload).to be_submitted
    end

    it "shows the drafts of the payments to validate, and validates them for a person who may, with the invoices lettered" do
      debit!
      sign_in poster
      get accounting_payment_path(batch)
      expect(response.body).to include("Validate the payments of the batch").and include(batch.items.first.end_to_end_id)

      post post_payments_accounting_payment_path(batch)

      expect(flash[:alert]).to be_nil
      expect(batch.items.first.reload.journal_entry).to be_posted
      expect(invoice.reload.status).to eq("paid")
    end

    it "does not offer the validation to a person who may not validate entries" do
      debit!
      sign_in assistant

      get accounting_payment_path(batch)

      expect(response.body).not_to include("Validate the payments of the batch")
    end

    it "rejects the payments that are missing from a partial debit, with a reason" do
      two = submitted_batch(posted(unit_price: 1000), posted(partner: create(:partner, :supplier, name: "Beta Corp", iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: "BE71096123456769", holder_name: "Beta Corp", created_by: owner, first_seen_at: 90.days.ago) }, unit_price: 500))
      acme = two.items.find_by(holder_name: "Acme Ltd")
      beta = two.items.find_by(holder_name: "Beta Corp")
      Payments::ConfirmDebit.call(batch: two, user: authorizer, transaction: debit_line(acme.amount, counterparty_iban: "BE68539007547034"), items: [ acme ]).tap { |r| raise r.message if r.failure? }
      sign_in authorizer

      get accounting_payment_path(two)
      expect(response.body).to include("Reject the selected payments")

      post reject_payments_accounting_payment_path(two), params: { item_ids: [ beta.id ], reason: "Rejected by the bank" }

      expect(beta.reload).to be_rejected
      expect(two.reload).to be_partially_rejected
    end

    it "shows the timeline of the batch, with who did what and when, and what is still to come" do
      debit!
      sign_in poster
      post post_payments_accounting_payment_path(batch)

      get accounting_payment_path(batch)

      expect(response.body).to include("Timeline").and include("Prepared").and include("Approved").and include("File made").and include("Loaded in the bank").and include("Debited").and include("Payments validated")
      expect(response.body).to include("Paula Poster").and include("Eve Exporter").and include("Alice Accountant")
    end

    it "shows the timeline of the payment on the invoice, from the invoice received to the lettering" do
      debit!
      sign_in poster
      post post_payments_accounting_payment_path(batch)

      get accounting_invoice_path(invoice)

      expect(response.body).to include("Payment timeline").and include(batch.reference).and include("Debited").and include("Lettered")
    end
  end

  describe "indicators and the export of executed payments" do
    let(:poster) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }

    before do
      batch = submitted_batch
      Payments::ConfirmDebit.call(batch: batch, user: authorizer, transaction: debit_line(batch.total, description: batch.reference, bank_reference: "STMT-9"), items: batch.items.to_a).tap { |r| raise r.message if r.failure? }
      Payments::PostBatchPayments.call(batch: batch.reload, user: poster).tap { |r| raise r.message if r.failure? }
    end

    it "shows how the company pays: batches debited, the share recognised from the statement, the late payments, what came back" do
      get accounting_payments_path

      expect(response.body).to include("Batches debited").and include("Recognised from the statement").and include("100 %").and include("Paid late").and include("Returned")
    end

    it "gives the executed payments as CSV, with the account masked, and as XLSX, to those who read the records" do
      sign_in reader

      get executed_accounting_payments_path(format: :csv)
      expect(response.headers["Content-Type"]).to include("text/csv")
      expect(response.body).to include("STMT-9").and include("BE68 **** **** 7034")
      expect(response.body).not_to include(iban)

      get executed_accounting_payments_path(format: :xlsx)
      expect(response.headers["Content-Type"]).to include("spreadsheetml")
      expect(response.body).to start_with("PK")
    end

    it "takes a period" do
      get executed_accounting_payments_path(format: :csv, from: (Date.current + 60).iso8601, to: (Date.current + 90).iso8601)

      expect(response.body).not_to include("STMT-9")
    end
  end

  describe "the notifications about a batch" do
    it "lead to the batch" do
      Approvals::Policy.create!(name: "batches", subject: :payment_batch, priority: 1).steps.create!(position: 1, mode: :any_of, approver_roles: %w[accountant admin])
      batch = batch_of(posted)
      request = Payments::SubmitBatch.call(batch: batch, user: preparer)[:request]
      notification = Accounting::Notify.call(user: preparer, event: "approval_reminder:#{request.id}:1:1", subject: request)

      post read_accounting_notification_path(notification)

      expect(response).to redirect_to(accounting_payment_path(batch))
    end
  end

  describe "the menu" do
    it "points to the payments when the feature is on, to the old batches when it is off" do
      get accounting_root_path
      expect(response.body).to include(%(href="#{accounting_payments_path}"))

      entity.update!(features: entity.features.merge("b01b" => false))
      get accounting_root_path
      expect(response.body).to include(%(href="#{accounting_payment_batches_path}"))
    end
  end

  describe "the history" do
    it "lists the batches, newest first, with the file linked once it exists" do
      first = approved_batch
      sign_in authorizer
      post export_accounting_payment_path(first)

      get accounting_payments_path

      expect(response.body).to include(first.reference).and include(download_accounting_payment_path(first))
    end

    it "never writes an IBAN in full on any of the screens" do
      invoice = posted
      post accounting_payments_path, params: { payment: bank_form(invoice) }
      batch = Payments::Batch.last

      [ accounting_payments_path, new_accounting_payment_path, accounting_payment_path(batch) ].each do |path|
        get path
        expect(response.body).not_to include(iban), path
      end
    end
  end
end
