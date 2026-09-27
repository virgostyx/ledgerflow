# docs/dev/reports/spec.md §2.4: "Aucun rapport sans scope société. Un spec
# vérifie qu'un utilisateur d'une autre société obtient zéro ligne." (adapted
# to this app's real tenant model: entity, not company).
#
# The including spec defines `rows_from_other_entity`: the query's result when
# called, from the current tenant, with a record (account/fiscal_year/...)
# that actually belongs to a *different* entity. acts_as_tenant's default
# scope on the underlying models should make that come back empty.
RSpec.shared_examples "entity scoped report" do
  it "returns nothing for another entity's records" do
    expect(rows_from_other_entity).to be_empty
  end
end
