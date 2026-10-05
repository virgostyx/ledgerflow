# F13a: accounts of the chart from a file, as custom accounts under an existing parent (the one named, else the longest account the
# code starts with) from which they take their class, type and normal balance. An account already there is skipped.
class Imports::Kinds::Accounts < Imports::Kind
  FIELDS = { "code" => true, "label_fr" => true, "label_nl" => false, "parent_code" => false, "reconcilable" => false }.freeze
  TRUE_WORDS = %w[1 true yes y oui x].freeze

  def analyze
    analysis = Imports::Analysis.blank
    analysis.read = @table.rows.size
    return analysis unless check_mapping!(analysis)

    known = Accounting::Account.pluck(:code).to_set
    @table.rows.each_with_index do |row, i|
      line, code, label = @table.lines[i], cell(row, "code"), cell(row, "label_fr")
      next analysis.refuse(code, line, "the code is missing") unless code
      next analysis.refuse(code, line, "the code must be digits, at most 10") unless code.match?(/\A\d{1,10}\z/)
      next analysis.refuse(code, line, "the label is missing") unless label
      next analysis.skipped << { ref: code, message: "already in the chart" } if known.include?(code)

      parent = cell(row, "parent_code") || known.select { |k| code.start_with?(k) && k != code }.max_by(&:length)
      next analysis.refuse(code, line, "no parent account: #{cell(row, 'parent_code') ? "#{parent} is unknown" : 'no account starts the code'}") unless parent && known.include?(parent)
      next analysis.refuse(code, line, "the code must start with the parent code #{parent}") unless code.start_with?(parent) && code != parent

      known << code
      analysis.items << { "code" => code, "label_fr" => label, "label_nl" => cell(row, "label_nl"), "parent_code" => parent,
                          "reconcilable" => TRUE_WORDS.include?(cell(row, "reconcilable").to_s.downcase) }
    end
    analysis
  end

  def self.write(items, batch:, user:)
    created = 0
    refused = []
    items.each do |attrs|
      ApplicationRecord.transaction(requires_new: true) do
        parent = Accounting::Account.find_by!(code: attrs["parent_code"])
        Accounting::Account.create!(parent: parent, code: attrs["code"], label_fr: attrs["label_fr"], label_nl: attrs["label_nl"], reconcilable: attrs["reconcilable"],
                                    account_class: parent.account_class, account_type: parent.account_type, normal_balance: parent.normal_balance,
                                    custom: true, is_leaf: true, active: true, import_batch_id: batch.id)
        created += 1
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
      refused << { ref: attrs["code"], lines: [], message: e.message }
    end
    { created: created, refused: refused }
  end
end
