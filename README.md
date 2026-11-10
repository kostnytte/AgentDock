# AgentDock

En liten lokal macOS-app som holder orden på arbeidsvinduer. Gi hvert vindu et navn, organiser dem i mapper og bytt raskt med tastatur eller mus. Flere vinduer fra samme app er separate valg.

AgentDock er skrevet i Swift/AppKit/SwiftUI uten eksterne pakkeavhengigheter. Krever **Apple Silicon og macOS 13 eller nyere**. Intel er ikke støttet av byggeskriptet.

## Kom i gang

For en ferdig utgivelse: last ned den notariserte ZIP-filen fra prosjektets GitHub Releases når en slik utgivelse finnes. Pakk ut og legg `AgentDock.app` i Programmer før første oppstart. Kildekodearkivet er ikke en ferdig app. En signert/notarisert binær er ikke publisert bare fordi kildekoden er tilgjengelig.

Åpne appen og slå på AgentDock i **Systeminnstillinger → Personvern og sikkerhet → Tilgjengelighet**. Tillatelsen trengs for vindusfunksjonene. App-/filsnarveier kan brukes uten den. Bare gi tilgang til appkopien du faktisk vil kjøre, og bruk én kopi om gangen.

Plussmenyen lar deg feste et åpent vindu, en app eller en fil. Appkort kan starte lukkede apper; filkort åpner i standardappen. Et appkort gjenskaper ikke en gammel agentsamtale.

## Bruk

- Menylinjeikonet åpner en midlertidig settekasse som lukkes når du velger et vindu eller klikker utenfor.
- Lag mapper og dra fra kortets håndtak til et mappenavn. Mapper organiserer kort; de er ikke filsystemmapper.
- Pause gir kortet mindre oppmerksomhet. Agenten og arbeidsvinduet fortsetter.
- Ta ut et kort eller arkiver flere samtidig uten å lukke arbeidsvinduer. Angre lar deg hente tilbake siste endring.
- Nettlesere vises per vindu, ikke per fane. Legg eventuelt en viktig fane i et eget vindu.
- Velgeren viser tilgjengelige aktive kort i valgt mappefilter. Velg **Alle** for å ta med alle mapper. Pausede, arkiverte og utilgjengelige kort vises ikke i velgeren selv om de finnes i settekassen.

| Hurtigtast | Handling |
| --- | --- |
| ⌥Tab / ⌥⇧Tab | Sentrert vindusvelger, fremover/bakover |
| Slipp ⌥ | Åpne markert kort |
| Flytt musen / klikk | Marker et kort / åpne direkte |
| ← / → i velgeren | Bytt kort |
| ↑ / ↓ i velgeren | Bytt mappefilter |
| ⌥Q i velgeren | Ta ut markert kort; arbeidsappen fortsetter |
| ⌃⌥Mellomrom | Vis/skjul settekassen |
| ⌃⌥A | Navngi og fest aktivt vindu i valgt mappe |
| ⌃⌥F | Søk i alle åpne vinduer |
| ⌃⌥1–9 | Åpne de første aktive kortene |

**AgentDock → Vis vindusvelger** lar velgeren stå åpen uten å holde Option. Bruk Enter eller klikk for å velge, Esc for å avbryte. I settekassen bruker du piltaster til kort og mapper. Venstre/høyre redigerer tekst normalt når søkefeltet har fokus.

Innen en økt følger kortet samme native vindu når tittelen endres. Etter omstart gjenkobles bare ett entydig treff på app og tittel. Like vindustitler kan kreve ny festing. «I fokus» betyr vindusfokus, ikke at en KI-agent arbeider.

## Personvern og tillatelser

Appen har ingen nettverksklient, server, analyse eller innlogging. Den leser vindusmetadata, ikke samtaletekst. Globale hurtigtaster og musedrag håndteres for navigering; appen logger ikke generell tastaturaktivitet. Tilgjengelighet gir likevel kraftig myndighet i macOS: bruk bare et bygg fra en avsender du stoler på.

**Vindustitler, navn, prosjekter og filstier lagres ukryptert lokalt.** De kan avsløre kunde- eller prosjektinformasjon. Ikke legg brukerdata, skjermbilder, nøkler eller private logger i repoet. Se [PRIVACY.md](PRIVACY.md) for nøyaktige datafiler og sletting, og [SECURITY.md](SECURITY.md) for sikkerhetsgrenser.

## Bygg og test

Installer Xcode eller Xcode Command Line Tools med Swift 5.9 eller nyere. Fra repoets rot:

```sh
zsh build.sh build-next
zsh test.sh
python3 -m unittest discover -s Tests -p 'test_*.py'
codesign --verify --strict build-next/AgentDock.app
```

Lokale bygg bruker ad hoc-signering og hardened runtime. Avslutt en tidligere appkopi før du prøver det nye bygget. Bruk en fast plassering i Programmer når du gir Tilgjengelighet-tilgang. Et nytt lokalt signert bygg kan kreve at samme app legges til på nytt i standardinnstillingene. Ikke slå av Gatekeeper, SIP eller andre sikkerhetsfunksjoner.

[Utgivelsesveiledningen](DISTRIBUTION.md) beskriver Developer ID-signering, Apple-notarisering, kontroll og ZIP-pakking. Utgivelsesverktøyet lager ingen distribusjonsfil før disse kontrollene består. Sertifikater og passord skal ligge i nøkkelringen, aldri i repoet.

## Utvikling og status

Se [agents.md](agents.md), [session-log.md](session-log.md) og [VALIDATION.md](VALIDATION.md). 0.11.1 klargjør offentlig kildekode og sikker utgivelsesflyt; eksisterende vindusfunksjoner og design er beholdt. Kildesjekken av 0.11 fant ingen rapporterbare sårbarheter i 31 gjennomgåtte filer. Dette er ingen sikkerhetsgaranti eller godkjenning av en senere binær.

MIT-lisens, se [LICENSE](LICENSE).
