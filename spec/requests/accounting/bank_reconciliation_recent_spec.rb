require "rails_helper"

# The lines already reconciled or waiting for validation, at the bottom of the screen (F02): a person who picked the wrong invoice finds the line again to undo it.
# Fifty of them, not ten, and a search on what the line says.
RSpec.describe "Bank reconciliation: finding a reconciled line again", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:bank_gl)      { create(:account, code: "550000", label_fr: "Banque", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:bank_journal) { create(:journal, :bank, default_account: bank_gl) }
  let(:bank_account)  { create(:bank_account, journal: bank_journal) }

  before do
    entity.update!(features: entity.features.merge("f02" => true)) if entity.respond_to?(:features)
    sign_in accountant
  end

  def reconciled(number, status: :reconciled)
    entry = create(:journal_entry, fiscal_year: fiscal_year, journal: bank_journal)
    create(:bank_transaction, bank_account: bank_account, amount: -10, status: status, journal_entry: entry, reference: "R-#{number}",
                              description: "Transfer VOL-ZMW1-#{format('%04d', number)}", updated_at: number.minutes.ago)
  end

  def listed = Nokogiri::HTML(response.body).css("td").map(&:text).grep(/VOL-ZMW1-\d+/).map { |t| t[/VOL-ZMW1-\d+/] }

  it "lists fifty lines, the most recently changed first" do
    (1..55).each { |n| reconciled(n) }

    get accounting_bank_reconciliation_path

    expect(listed.size).to eq(50)
    expect(listed.first).to eq("VOL-ZMW1-0001")
    expect(listed).not_to include("VOL-ZMW1-0055")
  end

  it "finds a line by what it says, beyond the fifty" do
    (1..55).each { |n| reconciled(n) }

    get accounting_bank_reconciliation_path, params: { rq: "zmw1-0055" }

    expect(listed).to eq([ "VOL-ZMW1-0055" ])
  end

  it "searches the lines waiting for validation too, and says nothing found when none matches" do
    reconciled(1, status: :matched)
    reconciled(2)

    get accounting_bank_reconciliation_path, params: { rq: "VOL-ZMW1-0001" }
    expect(listed).to eq([ "VOL-ZMW1-0001" ])

    get accounting_bank_reconciliation_path, params: { rq: "no such line" }
    expect(listed).to be_empty
    expect(response.body).to include("No booked line says")
  end

  it "does not filter the lines still to deal with" do
    pending_tx = create(:bank_transaction, bank_account: bank_account, amount: -5, description: "STILL PENDING LINE")

    get accounting_bank_reconciliation_path, params: { rq: "VOL-ZMW1" }

    expect(response.body).to include(pending_tx.description)
  end
end
