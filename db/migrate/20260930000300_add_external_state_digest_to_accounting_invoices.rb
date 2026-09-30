# Fingerprint of a draft as the API last wrote it (header, lines, analytical annotations). Recomputed later, a
# difference means the accountant has worked on the draft: a correction from the third party is then refused.
class AddExternalStateDigestToAccountingInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_invoices, :external_state_digest, :string
  end
end
