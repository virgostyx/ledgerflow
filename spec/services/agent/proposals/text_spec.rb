require "rails_helper"

# A11: the server's check of a drafted text, case by case. The figures, dates and numbers are checked in the runner; here, what the policy and the files allow.
RSpec.describe Agent::Proposals::Text do
  include_context "with open customer lines"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: as_of) }

  def payload(**overrides)
    { "kind" => "dunning_letter", "language" => "en", "subject" => "Payment reminder", "partner_id" => alice.id, "level" => 1,
      "body" => "Dear Alice,\n\nOur records show an invoice overdue. If you already paid it, please disregard this message.\n\nKind regards" }.merge(overrides.stringify_keys)
  end

  def check(**overrides) = described_class.call(payload(**overrides), context: context, today: as_of)

  before { open_line(partner: alice, amount: 100, days_overdue: 30) }

  it "accepts a reminder for a customer who may be reminded, and gives the normalized draft" do
    result = check

    expect(result).to be_valid
    expect(result.normalized).to include("kind" => "text", "text_kind" => "dunning_letter", "language" => "en", "partner_id" => alice.id, "level" => 1)
    expect(result.warnings.join).to include("never sent by itself")
  end

  describe "the reminder refused" do
    it "writes no reminder for a customer whose only line is in dispute, and says why" do
      Accounting::JournalEntryLine.update_all(disputed: true)

      result = check

      expect(result.errors.join).to include("Refused", "in dispute")
      expect(result.normalized).to be_nil
    end

    it "writes none for a line under a promise of payment that has not passed" do
      Accounting::JournalEntryLine.where.not(partner_id: nil).update_all(payment_promised_on: as_of + 5)

      expect(check.errors.join).to include("payment promised until")
    end

    it "writes none for a customer marked 'do not remind'" do
      alice.update!(do_not_dun: true)

      expect(check.errors.join).to include("do not remind")
    end

    it "writes none when nothing is overdue" do
      expect(check(partner_id: bob.id).errors.join).to include("Refused")
    end

    it "needs a level 1, 2 or 3" do
      expect(check(level: 7).errors.join).to include("level must be 1, 2 or 3")
    end
  end

  describe "what the policy of the company does not allow" do
    it "refuses late interest, a fixed indemnity and a threat that the policy does not carry, in three languages" do
      [ "We will charge late interest of 12 percent.", "A fixed indemnity of 10 percent applies.", "Otherwise we will send a bailiff.", "Bij gebreke zullen wij verwijlinteresten aanrekenen.", "Nous engagerons des poursuites." ].each do |sentence|
        result = check(body: "Dear Alice, #{sentence} Kind regards.")

        expect(result.errors.join).to include("does not allow"), sentence
      end
    end

    it "allows interest when the policy turned it on, and the formal step when the standard text of the level has it" do
      policy.update!(interest_enabled: true, interest_rate: 8)

      expect(check(body: "Dear Alice, late interest applies as agreed. Kind regards.")).to be_valid
      expect(check(level: 3, body: "Dear Alice, this is a formal notice. We will take further steps to recover the amounts due. Kind regards.")).to be_valid
    end

    it "warns that a higher level than the policy proposes is the person's choice" do
      expect(check(level: 3, body: "Dear Alice, please pay. Kind regards.").warnings.join).to include("a higher level is the person's choice")
    end
  end

  describe "what leaves the company" do
    it "refuses a text that repeats an internal note of the file, six words in a row" do
      Agent::MemoryNote.create!(scope_kind: "partner", scope_id: alice.id, text: "Alice is slow because her accountant is always late with the books.", category: "partner", author: user)

      result = check(body: "Dear Alice, we know that her accountant is always late with the books, so please pay. Kind regards.")

      expect(result.errors.join).to include("internal note or comment")
    end

    it "refuses the words of an internal comment" do
      task = Accounting::Task.create!(title: "Alice", kind: :other, status: :open, author: user)
      Accounting::Comment.create!(commentable: task, body: "Careful: this customer threatened to sue us last year over the contract.", author: user)

      expect(check(body: "Dear Alice, remember that this customer threatened to sue us last year over the contract. Kind regards.").errors.join).to include("internal note or comment")
    end

    it "lets a rewrite of the person's own text keep what it says: it does not leave the company" do
      Agent::MemoryNote.create!(scope_kind: "entity", text: "We always answer within two working days at the latest.", category: "convention", author: user)

      expect(check(kind: "rewrite", partner_id: nil, level: nil, body: "We always answer within two working days at the latest, as agreed.")).to be_valid
    end
  end

  describe "the rest" do
    it "needs a body, a language it writes, a kind it knows, and not too long a text" do
      expect(check(body: " ").errors.join).to include("body is required")
      expect(check(language: "de").errors.join).to include("language must be")
      expect(check(kind: "poem").errors.join).to include("kind must be")
      expect(check(body: "x" * 4001).errors.join).to include("too long")
    end

    it "warns of the placeholders to fill, a language other than the partner's, and a sensitive situation" do
      result = check(body: "Dear Alice, the invoice [To complete: invoice number] is overdue. We are sorry for the death of your partner. Kind regards.", language: "nl")

      expect(result.warnings.join).to include("1 placeholder(s)", "the text is in nl", "sensitive")
    end

    it "keeps the facts with a reference that opens something and drops the others, with a warning" do
      result = check(facts: [ { "label" => "Invoice", "value" => "INV-1", "ref" => "entry:5" }, { "label" => "Total", "value" => "1", "ref" => "https://evil.example/x" } ])

      expect(result.normalized["facts"]).to eq([ { "label" => "Invoice", "value" => "INV-1", "ref" => "entry:5" }, { "label" => "Total", "value" => "1" } ])
      expect(result.warnings.join).to include("not recognised")
    end

    it "warns when the closing formula of the profile is missing, and when the text is far longer than the target" do
      Agent::Setting.for_current_entity.update!(writing_profile: { "closing" => "With our best regards", "length_words" => 10 })

      expect(check(body: "Dear Alice, " + ("please pay. " * 20)).warnings.join).to include("closing formula", "longer than the target")
    end

    it "revises only a draft of the person that is still open" do
      other = Agent::TextDraft.create!(user: create(:user), kind: "rewrite", language: "en", payload: { "versions" => [] }.to_json)
      mine = Agent::TextDraft.create!(user: user, kind: "rewrite", language: "en", payload: { "versions" => [] }.to_json)

      expect(check(revises: other.id).errors.join).to include("revises must be")
      expect(check(revises: mine.id)).to be_valid
      mine.update!(status: "used")
      expect(check(revises: mine.id).errors.join).to include("revises must be")
    end
  end
end
