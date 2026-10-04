# What a step finds when it is evaluated (F10): its state now (:ok, :warning, :blocked, :pending) and the details to show, as a JSON-able hash.
Closing::Outcome = Struct.new(:status, :details) do
  def initialize(status, details = {}) = super
end
