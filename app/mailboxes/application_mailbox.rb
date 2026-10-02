class ApplicationMailbox < ActionMailbox::Base
  # The secret address of an entity's documents (F03): documents+<secret>@<domain>
  routing(/\Adocuments\+/i => :documents)
end
