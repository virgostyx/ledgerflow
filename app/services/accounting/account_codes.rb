module Accounting::AccountCodes
  CUSTOMERS       = "400000"
  SUPPLIERS       = "440000"
  VAT_DEDUCTIBLE     = "410100"
  VAT_PAYABLE        = "450100"
  VAT_NON_DEDUCTIBLE = "640400" # prorata: the non-recoverable share of purchase VAT
  CARRY_FORWARD   = "130000"
  TRANSIT         = "499000" # suspense account: nets to zero once an opening balance import is complete
  BANK_FEES       = "651100"
  RESULT          = "699000"
  ASSET_DISPOSAL  = "660100" # net book value of the fixed assets disposed of
  FX_LOSS         = "651200"
  FX_GAIN         = "751100"
end
