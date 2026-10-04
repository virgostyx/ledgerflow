# Step 8 of the closing (F10): stock.
class Closing::Steps::Stock < Closing::Step
  self.position = 8
  self.code     = "stock"
  self.title    = "Stock"
  self.kind     = :manual
  self.blocking = false
end
