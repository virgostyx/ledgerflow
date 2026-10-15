# ledger-verify

Verifies a package of LedgerFlow (the ZIP of a certificate of integrity of the `full` level) **without the application**. Plain Ruby: the standard library and OpenSSL, no gem,
no Rails, no network.

    ruby tools/ledger-verify/bin/ledger-verify PACKAGE [--fingerprint HEX] [--passphrase-env VAR | --passphrase-file FILE]
                                               [--authority-ca FILE] [--documents DIR] [--json]

Exit status: `0` PASS, `1` FAIL, `2` the command is wrong. It writes nothing to disk.

What it checks (each line of the output says what it found):

1. **manifest**: every file the manifest lists is there with its SHA-256, and nothing else is in the archive;
2. **signature**: the certificate's Ed25519 signature over its canonical form (RFC 8785), and that the key in it has the fingerprint it says;
3. **key_expected**: the fingerprint you give with `--fingerprint` (the one the issuer gave you *by another channel*) is the key's. Without it, the tool tells you the fingerprint to
   compare: a package that carries its own key proves nothing about who made it;
4. **entries**: for each entry its fingerprint recomputed from the canonical content, the debits equal to the credits, the places in the order of validation without a hole;
5. **anchors**: each anchor's hash, link, range, and the Merkle root (RFC 6962) recomputed from the entries; the last anchor is the one the certificate names;
6. **audit_chain**: the chain linked from the digests alone (version 2 of the chain; the older events only by their links), and tied to the anchors and the certificate;
7. **timestamps**: RFC 3161 tokens, with `openssl ts -verify`, given the certificate of the authority (`--authority-ca`);
8. **totals**: the totals of the certificate recomputed from the entries (the class of an account is read in `accounts.json`, which the certificate does not attest);
9. **documents**: with `--documents DIR`, each file compared with the fingerprints the package lists.

A package protected by a passphrase (`.zip.enc`, AES-256-GCM) is opened with it. A certificate alone (`certificate.json`, levels minimal and standard) has its signature checked
and the tool says that the rest cannot be.

What a PASS means, and does not, is written on the certificate. In short: the books were not altered since they were anchored; not that they are right.
