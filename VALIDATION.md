# Verifisering – AgentDock 0.11.1

Dato: 10. november 2026.

## Omfang

Offentlig dokumentasjon, kildepakke og utgivelsesflyt. Appens 18 Swift-kildefiler er uendret fra 0.11.0. Info.plist har versjon 0.11.1/build13. Ingen brukerdata er migrert eller hentet inn i repoet.

## Utførte kontroller

- 210 Swift-kontroller består på nytt: 40 lagring/modell, 73 board, 55 arbeidsflyt og 42 snarveier.
- 9 Python-tester består. De dekker manglende/tvetydig identitet, feil team/runtime/timestamp/debug-entitlement, Apple-avvisning, ticket-/Gatekeeper-feil, ny kontroll av utpakket ZIP og avvisning av private filer/stier/symlinker i kildeinventaret. Apple-kall er simulert.
- Kildeinventaret godkjenner 39 eksplisitte offentlige filer. Ingen faktiske kortdata, private maskinstier eller gjenkjennelige nøkkel-/tokenmønstre i disse filene.
- Lokalt arm64-bygg kompilerer, streng codesign-kontroll består og signaturdetaljer viser både adhoc og runtime. Bygget er kun et utviklingsbygg og er ikke notarisert.
- Bygg-/testskriptene består zsh-syntakskontroll.
- Alle 18 Swift-kildefiler er hash-sammenlignet med 0.11.0 og er identiske.
- En ekte kjøring av release.py stoppet før bygg/opplasting fordi denne kjøreflaten ikke har en tilgjengelig signeringsidentitet. Xcode viser et eksisterende Developer ID Application-sertifikat, men nøkkelringstilgang fra vanlig Terminal må verifiseres. Ingen notarisering er utført.

## Sikkerhetsgjennomgang

Statisk kildesjekk av 0.11: 31 filer gjennomgått; ingen rapporterbare sårbarheter eller innebygde hemmeligheter. Genererte binærer, gammel installer, historiske sikkerhetskopier og faktiske brukerdata var utenfor. Den private rapporten inneholder interne kildeplasseringer og inngår ikke i offentlig repo.

0.11.1 har ny utgivelseskode. Kontroll med simulerte Apple-verktøy verifiserer feilgrenser og publiseringsrekkefølge, men erstatter ikke en ekte Apple-innsending.

## Gjenstående praktisk verifisering

- Developer ID-signering, Apple-notarisering og ticket/Gatekeeper på den endelige distribusjonen.
- Førstegangsoppstart fra nedlastet ZIP på en annen Apple Silicon-Mac med Gatekeeper på.
- AX-tillatelse, fysisk Option-Tab/mus/slipp-Option, Option-Q og app-/filåpning i det endelige signerte bygget.
- Kortdrag og tittellinjedrag, flere vinduer fra samme app, flere skjermer og Spaces/fullskjerm.

Modelltester bruker injisert åpner; de beviser ikke at andre apper fysisk åpner en fil. Tidligere native preview bekreftet Option-Q uten avslutning. Verktøyet for museautomatisering var ustabilt; faktisk hover var derfor ikke fullt bekreftet. Ikke regn dette som utført etter bare en vellykket kompilering.
