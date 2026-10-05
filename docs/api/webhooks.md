# Webhooks sortants (F13c)

Un webhook est un appel que LedgerFlow fait à l'adresse que vous indiquez quand un événement a lieu. Réglages : *Settings > Webhooks* (propriétaire seul, société avec la fonction « Imports, exports and API »).

## Événements
`entry.posted`, `entry.reversed`, `reconciliation.created`, `period.locked`, `document.created`, `peppol.received`, `closing.completed`.

## L'appel
`POST` en JSON, en-têtes `X-LedgerFlow-Event`, `X-LedgerFlow-Event-Id`, `X-LedgerFlow-Delivery` et `X-LedgerFlow-Signature: t=<horodatage>,v1=<hex>`.

```json
{ "id": "5b7c…", "event": "entry.posted", "payload_version": 1, "created_at": "2026-10-05T07:00:00Z", "entity_id": 12,
  "data": { "id": 345, "reference": "OD2026/0042", "status": "posted", "entry_date": "2026-10-04", "journal": "OD", "fiscal_year": 2026, "reversal_of_id": null } }
```
`data` ne contient que des identifiants et un résumé; le reste se lit par l'API avec un jeton. `id` est le même pour toutes les livraisons d'un événement et pour ses renvois.

## Vérifier la signature
`v1` = HMAC-SHA256 hexadécimal de `"<horodatage>.<corps brut>"` avec le secret de l'abonnement. Calculer sur le **corps brut** (avant tout JSON.parse), comparer en temps constant, refuser un horodatage de plus de cinq minutes (cela empêche de rejouer un appel capturé). Après une rotation du secret, l'ancien signe encore pendant 24 h : l'en-tête contient alors **deux** `v1`, il suffit qu'un seul corresponde.

```ruby
def valid?(secret, header, raw_body)
  parts = header.to_s.split(",").map { |p| p.split("=", 2) }
  t = parts.assoc("t")&.last.to_i
  return false if (Time.now.to_i - t).abs > 300
  expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{t}.#{raw_body}")
  parts.select { |k, _| k == "v1" }.any? { |_, sig| ActiveSupport::SecurityUtils.secure_compare(sig, expected) }
end
```
Répondre `2xx` dans les 10 secondes. Tout autre résultat (ou aucune réponse) est un échec.

## Reprises, suspension, rejeu
Après un échec, nouvelles tentatives après 1 min, 5 min, 30 min, 2 h, 6 h, 12 h, 24 h (huit tentatives au plus), puis la livraison est abandonnée. Après un nombre réglable d'échecs de suite (10 par défaut), l'abonnement est **suspendu** : les propriétaires sont prévenus, les nouveaux événements ne partent plus. Le journal des livraisons (page de l'abonnement) montre chaque tentative et permet de renvoyer une livraison (même `id` d'événement).

## Adresses admises
`https` seulement, vers une adresse **publique** : pas d'identifiants dans l'URL, pas de réseau privé, de boucle locale ni d'adresse locale de lien. Le nom est résolu à l'enregistrement et à chaque envoi, et la connexion va à l'adresse contrôlée.
