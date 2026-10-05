module Accounting::AccountCodes
  CUSTOMERS       = "400000"
  SUPPLIERS       = "440000"
  VAT_DEDUCTIBLE     = "410100"
  VAT_PAYABLE        = "450100"
  VAT_NON_DEDUCTIBLE = "640400" # prorata: the non-recoverable share of purchase VAT
  CARRY_FORWARD   = "130000"
  LEGAL_RESERVE   = "130100" # the legal reserve, fed by the appropriation of the result after a closing (F10)
  # Suspense account: nets to zero once an opening balance import is complete; also holds the lines of an API invoice
  # still to be coded by the accountant (posting is refused meanwhile).
  TRANSIT         = "499000"
  BANK_FEES       = "651100"
  RESULT          = "699000"
  ASSET_DISPOSAL  = "660100" # net book value of the fixed assets disposed of
  FX_LOSS         = "651200"
  FX_GAIN         = "751100"
  INTERNAL_TRANSFERS = "580000" # transit account of the transfers between two bank accounts of the entity (F02)
  ROUNDING_LOSS   = "658100" # rounding differences of the bank payments (F02), created by the owner on existing entities
  ROUNDING_GAIN   = "758100"
  FX_UNREALIZED_GAIN = "499200" # balance-sheet counterpart of the unrealized exchange gains, when the entity chooses to defer or recognize them (F11)
  FX_DEFERRED_GAIN   = "492200" # "Produits à reporter": where a deferred unrealized gain waits
  FX_UNREALIZED   = "499100" # balance-sheet counterpart of the unrealized exchange losses booked at closing
end
