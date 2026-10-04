# Step 10 of the closing (F10): taxes.
class Closing::Steps::Taxes < Closing::Step
  self.position = 10
  self.code     = "taxes"
  self.title    = "Taxes"
  self.kind     = :manual
  self.blocking = false
end
