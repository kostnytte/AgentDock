# AgentDock – offentlig utviklingslogg

Denne loggen inneholder generell produkthistorikk. Private maskinstier, kundevinduer, installasjonskvitteringer og eldre arbeidslogger inngår ikke i repoet.

## 2026-11-10 – klargjøring for offentlig kildekode, 0.11.1

Bestilling: klargjør kildekoden for åpen deling og sett opp Apple-signering/notarisering. Eksisterende funksjoner og design skal bevares.

- Offentlig README, utviklingsinstruksjoner, personverndokumentasjon, sikkerhetsgrenser og MIT-lisens.
- Forklarer bred AX-tillatelse og at titler, navn og målsti lagres i klartekst lokalt. Korrigerer at snarveistier også ligger i board.json.
- Git-ignore og eksplisitt kildeinventar beskytter mot utilsiktet pakking av runtime-data, nøkler, eldre logger, sikkerhetskopier og byggeprodukter.
- Lokale bygg aktiverer hardened runtime. Utgivelsesflyten krever Developer ID Application, timestamp, godkjent Apple-notarisering, ticket, Gatekeeper og ny kontroll etter utpakking.
- Appens 18 Swift-kildefiler er uendret fra 0.11.0. Ingen migrering av brukerdata eller UI-endring.

210 Swift-kontroller og 9 Python-tester består; lokalt arm64-bygg, hardened runtime og streng signaturkontroll er bekreftet. 39 offentlige filer består kildeinventarkontrollen. Valideringsresultater og gjenværende begrensninger står i VALIDATION.md. Signert/notarisert utgivelse skal ikke hevdes før den er utført. Neste steg er å kjøre utgivelsesflyten med utviklerkontoens nøkkelringprofil og prøve resultatet på en annen Mac.

## Tidligere funksjoner

- 0.11.0: musevalg og lokal Option-Q-fjerning i den sentrerte vindusvelgeren; 210 modell-/integrasjonskontroller.
- 0.10.1: fjernet den store sentrerte tittelen under vinduskortene.
- 0.10: app-/filkort med bokmerker, reparasjon av mål og åpning via NSWorkspace uten AX-krav.
- 0.9: navn/mappe ved festing, mappefilter i velgeren, søk i alle åpne vinduer og arkiv.
- 0.5–0.8: mapper, tastaturnavigering, egen vindusvelger, fest aktivt vindu og kortdrag til mappe.

Historiske testresultater er ikke en påstand om at hver gest, macOS-versjon eller binær er ende-til-ende-verifisert.
