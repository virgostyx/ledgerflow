# Customer reminders (F09): seen by anyone who sees the records; prepared and edited by those who prepare (`dunning.prepare`); validated and sent, and a
# bounce recorded, by those who send (`dunning.send`), a distinct right: a reminder speaks for the entity.
class Accounting::DunningRunPolicy < ApplicationPolicy
  def index?    = can?("records.view")
  def show?     = can?("records.view")
  def create?   = can?("dunning.prepare")
  def update?   = can?("dunning.prepare")
  def send_run? = can?("dunning.send")
  def bounce?   = can?("dunning.send")
end
