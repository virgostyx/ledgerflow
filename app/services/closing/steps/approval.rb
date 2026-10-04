# Step 18 of the closing (F10): approval.
class Closing::Steps::Approval < Closing::Step
  self.position = 18
  self.code     = "approval"
  self.title    = "Approval"
  self.kind     = :manual
  self.blocking = true
end
