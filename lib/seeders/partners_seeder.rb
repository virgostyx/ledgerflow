module Seeders
  class PartnersSeeder
    SUPPLIERS = [
      {
        name:         "Proximus NV",
        partner_type: :supplier,
        vat_number:   "BE0202239951",
        email:        "facturation@proximus.be",
        phone:        "+32 2 202 41 11",
        street:       "Boulevard du Roi Albert II 27",
        city:         "Bruxelles",
        zip:          "1030",
        country:      "BE",
        iban:         "BE71096000049734",
        bic:          "JVBABE22",
        notes:        "Opérateur télécom — lignes fixes, mobiles et internet"
      },
      {
        name:         "Engie Belgium SA",
        partner_type: :supplier,
        vat_number:   "BE0403170701",
        email:        "clients.business@engie.be",
        phone:        "+32 2 510 80 00",
        street:       "Avenue Ariane 7",
        city:         "Bruxelles",
        zip:          "1200",
        country:      "BE",
        iban:         "BE45068009338471",
        bic:          "NICABEBB",
        notes:        "Fournisseur d'énergie — électricité et gaz naturel"
      },
      {
        name:         "bpost SA",
        partner_type: :supplier,
        vat_number:   "BE0214596464",
        email:        "business@bpost.be",
        phone:        "+32 2 278 50 00",
        street:       "Centre Monnaie",
        city:         "Bruxelles",
        zip:          "1000",
        country:      "BE",
        iban:         "BE77096000085988",
        bic:          "JVBABE22",
        notes:        "Services postaux et de courrier"
      },
      {
        name:         "Sodexo Belgium SA",
        partner_type: :supplier,
        vat_number:   "BE0403584834",
        email:        "be.business@sodexo.com",
        phone:        "+32 2 547 55 11",
        street:       "Rue Royale 100",
        city:         "Bruxelles",
        zip:          "1000",
        country:      "BE",
        iban:         "BE55310126986468",
        bic:          "BBRUBEBB",
        notes:        "Titres-repas et services aux entreprises"
      },
      {
        name:         "Lyreco Belgium NV",
        partner_type: :supplier,
        vat_number:   "BE0406006593",
        email:        "service.clients@lyreco.com",
        phone:        "+32 15 28 28 28",
        street:       "Industrieweg 6",
        city:         "Mechelen",
        zip:          "2800",
        country:      "BE",
        iban:         "BE56293041272220",
        bic:          "GEBABEBB",
        notes:        "Fournitures de bureau et papeterie"
      },
      {
        name:         "Carglass Belgium NV",
        partner_type: :supplier,
        vat_number:   "BE0400461640",
        email:        "fleet@carglass.be",
        phone:        "+32 2 252 80 90",
        street:       "Chaussée de Louvain 431",
        city:         "Wavre",
        zip:          "1300",
        country:      "BE",
        iban:         "BE87001556987123",
        bic:          "GEBABEBB",
        notes:        "Entretien et réparation de véhicules de société"
      }
    ].freeze

    def self.call
      new.call
    end

    def call
      counts = { created: 0, skipped: 0 }

      SUPPLIERS.each do |attrs|
        partner = Accounting::Partner.find_or_initialize_by(vat_number: attrs[:vat_number])
        if partner.new_record?
          partner.assign_attributes(attrs)
          partner.save!
          counts[:created] += 1
        else
          counts[:skipped] += 1
        end
      end

      puts "[Partners] #{counts[:created]} fournisseurs créés, #{counts[:skipped]} déjà présents."
    end
  end
end
