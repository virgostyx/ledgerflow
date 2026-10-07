require "rails_helper"

# A04: what leaves for the language model, class of data by class of data. Every example looks at the payload itself, as the provider would receive it.
RSpec.describe Agent::Redactor do
  include_context "with entity"

  let(:conversation) { Agent::Conversation.create!(user: create(:user), title: "t") }
  let(:setting) { Agent::Setting.for_current_entity }
  let(:iban) { "BE68539007547034" }
  let(:vat) { "BE0#{format('%07d', 1_234_567)}#{format('%02d', 97 - 1_234_567 % 97)}" }
  let(:national_number) { "850731001#{format('%02d', 97 - 850731001 % 97)}" }

  subject(:redactor) { described_class.new(setting: setting, conversation: conversation) }

  def redact(text) = redactor.redact(system: "system", messages: [ { role: "user", content: text } ]).messages.first[:content]

  def with_modes(modes) = setting.update!(data_class_modes: modes)

  describe "an IBAN, class bank_identifier" do
    it "keeps its last four characters by default" do
      expect(redact("Pay #{iban} now, or #{iban.scan(/.{4}/).join(' ')}")).to eq("Pay IBAN …7034 now, or IBAN …7034")
    end

    it "is never sent in block mode" do
      with_modes("bank_identifier" => "block")

      expect(redact("Pay #{iban}")).to eq("Pay [IBAN blocked]")
    end

    it "goes as it is in send mode" do
      with_modes("bank_identifier" => "send")

      expect(redact("Pay #{iban}")).to eq("Pay #{iban}")
    end

    it "leaves a number that only looks like one" do
      expect(redact("ref BE68539007547035")).to eq("ref BE68539007547035")
    end
  end

  describe "a national number, class personal" do
    it "is replaced, and never sent in block mode" do
      expect(redact("born #{national_number}")).to eq("born [national number]")
      with_modes("personal" => "block")
      expect(redact("born #{national_number}")).to eq("born [national number blocked]")
    end

    it "leaves a number whose check digits are wrong" do
      expect(redact("amount 12345678901")).to eq("amount 12345678901")
    end
  end

  describe "a VAT number, class tax_identifier" do
    it "becomes a token, the same one every time, and block mode removes it" do
      expect(redact("supplier #{vat} and again #{vat}")).to eq("supplier TVA_001 and again TVA_001")
      with_modes("tax_identifier" => "block")
      expect(redact("supplier #{vat}")).to eq("supplier [VAT blocked]")
    end

    it "also finds a foreign one" do
      expect(redact("client NL123456789B01")).to eq("client TVA_001")
    end
  end

  describe "a bank card number or a password, which never go" do
    it "are removed whatever the settings" do
      with_modes("bank_identifier" => "send", "personal" => "send", "tax_identifier" => "send")

      expect(redact("card 4111 1111 1111 1111 and password: hunter2")).to eq("card [card number blocked] and password: [secret blocked]")
    end

    it "are removed from what a tool returned as well" do
      leaky = [ { role: "user", content: [ { type: "tool_result", tool_use_id: "x", content: { "data" => [ { "description" => "paid with 4111111111111111" } ] }.to_json, is_error: false } ] } ]

      expect(redactor.redact(system: "s", messages: leaky).messages.first[:content].first[:content]).to include("[card number blocked]")
    end
  end

  describe "the name of a partner, class personal" do
    let!(:alice)   { create(:partner, name: "Alice Dupont", is_natural_person: true) }
    let!(:unknown) { create(:partner, name: "Bob Martin", is_natural_person: nil) }
    let!(:company) { create(:partner, name: "Acme Industries SA", is_natural_person: false) }

    it "is replaced by a token when the partner is a natural person, or not known: the prudent reading" do
      expect(redact("Alice Dupont owes 10 and bob martin owes 5")).to eq("PERSONNE_001 owes 10 and PERSONNE_002 owes 5")
    end

    it "is left alone when the partner is a company" do
      expect(redact("Acme Industries SA owes 10")).to eq("Acme Industries SA owes 10")
    end

    it "is the same token in the whole conversation, in a later question as in this one" do
      redact("Alice Dupont")

      expect(described_class.new(setting: setting, conversation: conversation).redact(system: "s", messages: [ { role: "user", content: "again Alice Dupont" } ]).messages.first[:content]).to eq("again PERSONNE_001")
    end

    it "does not cut a word that only contains the name" do
      expect(redact("Alice Dupontel is someone else")).to eq("Alice Dupontel is someone else")
    end

    it "is never sent in block mode" do
      with_modes("personal" => "block")

      expect(redact("Alice Dupont owes 10")).to eq("[name blocked] owes 10")
    end

    it "goes as it is in send mode" do
      with_modes("personal" => "send")

      expect(redact("Alice Dupont owes 10")).to eq("Alice Dupont owes 10")
    end

    it "is never sent in block mode or restricted mode even when the partner is a company: no name of a third party at all" do
      with_modes("personal" => "block")

      expect(redact("Acme Industries SA owes 10")).to eq("[name blocked] owes 10")
      setting.update!(data_class_modes: {}, restricted: true)
      expect(redact("Acme Industries SA owes 10")).to eq("[name blocked] owes 10")
    end

    it "is hidden from the model but read again by the person: the answer's tokens come back as names" do
      redact("Alice Dupont")

      expect(conversation.reveal("PERSONNE_001 owes 10")).to eq("Alice Dupont owes 10")
    end
  end

  describe "the result of a tool" do
    let!(:alice) { create(:partner, name: "Alice Dupont", is_natural_person: true, vat_number: nil) }
    let(:messages) do
      result = { "data" => [ { "name" => "Alice Dupont", "vat_number" => vat, "city" => "Namur", "type" => "customer", "ref" => "partner:1" } ], "totals" => { "total" => "1210.50", "ref" => "R04:2026-09-26:customer:total" },
                 "as_of" => "2026-09-26", "row_count" => 1 }
      [ { role: "user", content: "who?" },
        { role: "assistant", content: [ { type: "tool_use", id: "t1", name: "search_partners", input: { "q" => "Dupont" } } ] },
        { role: "user", content: [ { type: "tool_result", tool_use_id: "t1", content: result.to_json, is_error: false } ] } ]
    end

    def sent(messages_in = messages) = JSON.parse(redactor.redact(system: "s", messages: messages_in).messages.last[:content].first[:content])

    it "masks the fields the tool declared, by their class: the name, the VAT number" do
      row = sent["data"].first

      expect(row).to include("name" => "PERSONNE_001", "vat_number" => "TVA_001", "city" => "Namur", "type" => "customer", "ref" => "partner:1")
    end

    it "keeps the figures, the dates and the references, the structure and the row count" do
      expect(sent).to include("totals" => { "total" => "1210.50", "ref" => "R04:2026-09-26:customer:total" }, "as_of" => "2026-09-26", "row_count" => 1)
    end

    it "leaves the tool's call as the model made it: tokens, never real values" do
      assistant = redactor.redact(system: "s", messages: messages).messages[1][:content].first

      expect(assistant[:input]).to eq("q" => "Dupont")
    end

    it "is never sent in block mode for a class, whatever the tool" do
      with_modes("personal" => "block", "tax_identifier" => "block", "free_text" => "block")

      expect(sent["data"].first).to include("name" => "[blocked]", "vat_number" => "[blocked]")
    end

    it "holds back every amount and date when the entity does not let figures go" do
      with_modes("financial" => "block")

      expect(sent).to include("totals" => { "total" => "[blocked]", "ref" => "R04:2026-09-26:customer:total" }, "as_of" => "[blocked]", "row_count" => 1)
    end

    it "holds back the references when the entity does not let them go" do
      with_modes("public_ref" => "block")

      expect(sent["data"].first["ref"]).to eq("[blocked]")
      expect(sent["totals"]["ref"]).to eq("[blocked]")
    end

    it "sends only aggregates in restricted mode: no name, no identifier, no free text, and the figures still there" do
      setting.update!(restricted: true, data_class_modes: { "personal" => "send" })

      expect(sent["data"].first).to include("name" => "[blocked]", "vat_number" => "[blocked]")
      expect(sent["totals"]["total"]).to eq("1210.50")
    end

    it "sweeps what a field of free text holds, whatever the class declared: an IBAN, a number" do
      leaky = [ messages[0], messages[1], { role: "user", content: [ { type: "tool_result", tool_use_id: "t1", content: { "data" => [ { "description" => "Pay #{iban} to #{vat}" } ] }.to_json, is_error: false } ] } ]

      expect(sent(leaky)["data"].first["description"]).to eq("Pay IBAN …7034 to TVA_001")
    end

    it "treats a result that is not JSON as a text" do
      text = [ { role: "user", content: [ { type: "tool_result", tool_use_id: "t9", content: "plain #{iban}", is_error: false } ] } ]

      expect(redactor.redact(system: "s", messages: text).messages.first[:content].first[:content]).to eq("plain IBAN …7034")
    end

    it "does not change the messages it is given" do
      original = Marshal.load(Marshal.dump(messages))

      redactor.redact(system: "s", messages: messages)

      expect(messages).to eq(original)
    end
  end

  describe "the system prompt" do
    it "is swept too" do
      expect(redactor.redact(system: "Entity of #{iban}", messages: []).system).to eq("Entity of IBAN …7034")
    end
  end

  describe "the record of what was done" do
    let!(:alice) { create(:partner, name: "Alice Dupont", is_natural_person: true) }

    it "counts the values masked or blocked, by class of data, without keeping any of them" do
      stats = redactor.redact(system: "s", messages: [ { role: "user", content: "Alice Dupont, #{iban}, #{vat}, #{national_number}" } ]).stats

      expect(stats).to eq("personal" => { "masked" => 2 }, "bank_identifier" => { "masked" => 1 }, "tax_identifier" => { "masked" => 1 })
      expect(stats.to_s).not_to include("Alice", "7034")
    end

    it "starts afresh at every payload" do
      redactor.redact(system: "s", messages: [ { role: "user", content: iban } ])

      expect(redactor.redact(system: "s", messages: [ { role: "user", content: "nothing" } ]).stats).to eq({})
    end
  end

  describe "a property: no complete IBAN is left in what goes out when the class is masked or blocked" do
    let(:rng) { Random.new(42) }

    def random_iban
      account = Array.new(10) { rng.rand(10) }.join
      check = 98 - (("#{account}111400".to_i) % 97)
      "BE#{format('%02d', check)}#{account}"
    end

    %w[mask block].each do |mode|
      it "holds for 200 random texts in #{mode} mode" do
        with_modes("bank_identifier" => mode)
        200.times do
          ibans = Array.new(rng.rand(1..3)) { random_iban }
          text = ibans.zip(%w[pay to from on ref]).map { |code, word| "#{word} #{rng.rand < 0.5 ? code : code.scan(/.{1,4}/).join(' ')}" }.join("; ")

          out = redact(text)

          ibans.each { |code| expect(out.delete(" ")).not_to include(code) }
          expect(Agent::Identifiers.ibans(out)).to be_empty
        end
      end
    end
  end
end
