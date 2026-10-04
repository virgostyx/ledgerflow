# Step 9 of the closing (F10): provisions and doubtful debts.
class Closing::Steps::Provisions < Closing::Step
  self.position = 9
  self.code     = "provisions"
  self.title    = "Provisions and doubtful debts"
  self.kind     = :manual
  self.blocking = false
end
