# B02c: the text a client reads, and agrees to, before approving accounts, in the three languages of the portal. It is consigned, whole, with the proof (and its SHA-256).
# **DRAFT: the wording is not legal advice and has not been read by a lawyer** (docs/dev/signature/QUESTIONS.md, B02c). It states what the approval is not: a qualified electronic signature,
# nor the approval of the annual accounts by the competent body of the company.
module Portal::ApprovalText
  VERSION = "2026-10-draft-1".freeze

  TEXTS = {
    "en" => "By approving, I confirm that I opened and read the documents listed below, and that they match what I know of the company. This approval is a confirmation given through this portal, " \
            "after a second authentication. It is not a qualified electronic signature, and it is not the approval of the annual accounts by the competent body of the company (for example the general meeting).",
    "fr" => "En approuvant, je confirme avoir ouvert et lu les documents listés ci-dessous, et qu'ils correspondent à ce que je connais de la société. Cette approbation est une confirmation donnée " \
            "par ce portail, après une seconde authentification. Ce n'est ni une signature électronique qualifiée, ni l'approbation des comptes annuels par l'organe compétent de la société (par exemple l'assemblée générale).",
    "nl" => "Door goed te keuren bevestig ik dat ik de hieronder vermelde documenten heb geopend en gelezen, en dat ze overeenkomen met wat ik van de vennootschap weet. Deze goedkeuring is een bevestiging " \
            "via dit portaal, na een tweede authenticatie. Het is geen gekwalificeerde elektronische handtekening en geen goedkeuring van de jaarrekening door het bevoegde orgaan van de vennootschap (bijvoorbeeld de algemene vergadering)."
  }.freeze

  def self.for(locale) = TEXTS.fetch(locale.to_s) { TEXTS.fetch("en") }
end
