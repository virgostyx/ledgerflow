# Guided imports (F13a): whoever may import (`imports.manage`) sees the batches, makes one and takes one back. A bank statement batch (F02) is not
# listed here: the guided imports are the batches that have a kind.
class Accounting::ImportBatchPolicy < ApplicationPolicy
  def index?  = can?("imports.manage")
  def show?   = can?("imports.manage")
  def create? = can?("imports.manage")
  def update? = can?("imports.manage")
  def undo?   = can?("imports.manage")
end
