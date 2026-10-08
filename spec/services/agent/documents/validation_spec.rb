require "rails_helper"

RSpec.describe Agent::Documents::Validation do
  let(:vat) { "BE0#{format('%07d', 1_234_567)}#{format('%02d', 97 - (1_234_567 % 97))}" }
  let(:fields) { { "supplier_vat" => vat, "iban" => "BE68539007547034", "invoice_date" => "2026-03-15", "due_date" => "2026-04-14", "subtotal" => "1000.00", "vat_amount" => "210.00", "total" => "1210.00" } }

  def check(fields, **options) = described_class.call(fields, today: Date.new(2026, 6, 1), **options)

  it "finds a document in order valid" do
    result = check(fields, lines: [ { "net" => "600.00" }, { "net" => "400.00" } ], breakdown: [ { "rate" => "21", "base" => "1000.00", "vat" => "210.00" } ])

    expect(result.fields.values.map { |verdict| verdict["status"] }).to all(eq("valid"))
    expect(result.document.values.map { |verdict| verdict["status"] }).to all(eq("valid"))
  end

  it "refuses an IBAN, a Belgian VAT number and a structured communication whose check digits fail" do
    result = check(fields.merge("iban" => "BE68539007547035", "supplier_vat" => "BE0123456780", "structured_communication" => "+++090/9337/55494+++"))

    %w[iban supplier_vat structured_communication].each { |name| expect(result.fields[name]["status"]).to eq("invalid"), name }
  end

  it "does not claim to check the digits of a foreign VAT number" do
    expect(check(fields.merge("supplier_vat" => "FR12345678901")).fields["supplier_vat"]["status"]).to eq("unchecked")
  end

  it "refuses implausible dates: before 2000, a year ahead, a due date before the invoice date" do
    result = check(fields.merge("invoice_date" => "1999-01-01", "due_date" => "2028-01-01"))

    expect(result.fields["invoice_date"]["reason"]).to include("2000")
    expect(result.fields["due_date"]["reason"]).to include("year ahead")
    expect(check(fields.merge("due_date" => "2026-03-01")).fields["due_date"]["reason"]).to include("before the invoice date")
  end

  it "adds the lines up to the subtotal, and the subtotal and VAT up to the total, to the cent and within five cents" do
    expect(check(fields, lines: [ { "net" => "600.00" }, { "net" => "399.97" } ]).document["lines_add_up_to_subtotal"]["status"]).to eq("valid")
    expect(check(fields, lines: [ { "net" => "600.00" }, { "net" => "399.00" } ]).document["lines_add_up_to_subtotal"]["status"]).to eq("invalid")
    expect(check(fields.merge("total" => "1210.10")).document["subtotal_plus_vat_is_total"]["status"]).to eq("invalid")
  end

  it "checks the VAT of each rate" do
    result = check(fields, breakdown: [ { "rate" => "6", "base" => "100.00", "vat" => "6.00" }, { "rate" => "21", "base" => "100.00", "vat" => "20.00" } ])

    expect(result.document["vat_rate_6"]["status"]).to eq("valid")
    expect(result.document["vat_rate_21"]["status"]).to eq("invalid")
  end

  it "refuses a negative amount" do
    expect(check(fields.merge("vat_amount" => "-1.00")).fields["vat_amount"]["status"]).to eq("invalid")
  end
end
