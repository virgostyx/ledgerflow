# Before sending: the document built is checked (Peppol::UblRules, not the official Schematron: see there). One that breaks a rule is never sent,
# nor sent again as it is: it fails with the rules it breaks, in words the person can act on.
class Peppol::Actions::ValidateUbl
  extend LightService::Action

  expects :ubl_xml

  executed do |ctx|
    problems = Peppol::UblRules.call(ctx.ubl_xml)
    ctx.fail!(I18n.t("peppol.errors.invalid_ubl", problems: problems.join("; "))) if problems.any?
  end
end
