# Signering og utgivelse

Kildekode kan bygges lokalt med `zsh build.sh build-next`. Del bare en ferdig binær når hele utgivelsesflyten nedenfor har bestått.

## Engangsoppsett i vanlig Terminal

1. Bruk Xcode → Settings → Apple Accounts → ditt team → Manage Certificates. Du trenger et **Developer ID Application**-sertifikat med tilhørende privat nøkkel på denne Mac-en. Apple Development og Developer ID Installer erstatter ikke dette. Ikke opprett eller tilbakekall sertifikater som allerede fungerer.
2. Kontroller tilgjengelig identitet:

```sh
security find-identity -v -p codesigning
```

3. Lag en notarisering-profil i macOS-nøkkelringen. Kommandoen spør interaktivt etter Apple-konto, team-ID og et appspesifikt passord:

```sh
xcrun notarytool store-credentials AgentDock-notary
```

Opprett et appspesifikt passord på Apples kontoside hvis du trenger det. Skriv det bare i den sikre Terminal-prompten. Ikke lim passord, privat nøkkel eller API-nøkkel inn i kode, chat, shell-historikk eller en `.env` som kan bli publisert. Profilen må tilhøre samme utviklerteam som signeringssertifikatet.

## Lag en utgivelse

Fra prosjektroten:

```sh
python3 scripts/release.py
```

Ved flere gyldige Developer ID Application-identiteter velger du SHA-1-en fra `security find-identity`:

```sh
python3 scripts/release.py --identity SERTIFIKATETS_SHA1 --profile AgentDock-notary
```

Verktøyet:

1. Krever en gyldig Developer ID Application-identitet og nøkkelringprofil; ingen automatisk retur til ad hoc-signering.
2. Kjører Swift-testene og bygger med hardened runtime og sikker timestamp.
3. Verifiserer signatur, bundle-ID, TeamIdentifier, timestamp og at ingen debug-entitlement er slått på.
4. Sender en ZIP av appen til Apples notariseringstjeneste og krever status `Accepted`.
5. Hefter ticket på appen, validerer den og krever godkjent Gatekeeper-vurdering.
6. Pakker den ferdige appen på nytt, validerer en utpakket kopi og lager SHA-256 og en lokal kvittering.

Ferdig resultat ligger under `dist/AgentDock-<versjon>/AgentDock-<versjon>-macOS-arm64.zip`, med `SHA256SUMS` og `release-receipt.json` i samme mappe. `dist/` er ignorert av Git. Utgivelsesmappen bygges i en midlertidig katalog og publiseres samlet etter alle kontroller. En eksisterende utgivelsesmappe overskrives ikke. Utestående innsendelse, avvist notarisering, manglende profil eller nøkkelringstilgang gir feilstatus og ingen ny distribusjonsfil. Apple kan bruke tid; en kvittering fra mislykket innsending lagres under `build-release/` slik at innsendings-ID kan undersøkes.

Last opp ZIP og SHA256SUMS til en GitHub Release når kontrollene består. Ikke last opp hele prosjektmappen eller lokale notary-logger. Prøv oppstart, tillatelse og vindusbytte på en annen Mac før du kaller utgivelsen ferdig testet. Ikke be brukere deaktivere Gatekeeper eller SIP.

## Verifiser nedlastingen

Pakk ZIP-filen ut og kontroller appen:

```sh
shasum -a 256 -c SHA256SUMS
codesign --verify --strict AgentDock.app
xcrun stapler validate AgentDock.app
spctl --assess --type execute --verbose=2 AgentDock.app
```

SHA-256 oppdager endrede nedlastinger, men autentiserer ikke alene avsenderen. Developer ID og Apples ticket er separate kontroller. Apple-notarisering er en automatisk kontroll av blant annet skadevare og signering, ikke en full sikkerhetsrevisjon.

Offisielle referanser: [Developer ID](https://developer.apple.com/developer-id/), [notarisering](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [sertifikater](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
