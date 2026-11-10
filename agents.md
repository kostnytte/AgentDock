# AgentDock – videre utvikling

## Start her

Bruk repoets rot som prosjektrot. Les README.md, session-log.md, PRIVACY.md, SECURITY.md og VALIDATION.md før endringer. Prosjektet er Swift/AppKit/SwiftUI, uten eksterne pakker. Bygges med swiftc gjennom build.sh; ikke bytt byggesystem for små endringer.

## Produktkontrakt

Bevar eksisterende design og rask flyt. Settekassen er en transient NSPopover, mens den sentrerte vindusvelgeren er et eget panel. Flere vinduer fra samme app skal forbli separate valg. Ikke gjeninnfør stor sentrert tittel under kortene. Pause, ta ut og arkiv gjelder bare AgentDock, ikke arbeidsappen eller agentens kjøring.

Mapper, kortnavn, UUID-er, rekkefølge, pause og snarveimål skal bevares. App-/filkort kan starte lukkede mål, men gjenskaper ikke automatisk en gammel samtale. Mapper i AgentDock er ikke filsystemmapper. Nettlesere vises per vindu.

Option-Tab/Shift-Tab, mus, piltaster, Enter og Esc skal dele kortvalg uten at en stillestående peker stjeler markeringen. Musevalg skal ikke rulle kortet bort. Option-Q er lokal bare i den aktive velgeren, ignorerer tastaturrepetisjon og skal aldri sende lukk/avslutt til andre apper. Fjern etter vellykket lagring, bevar Angre og behandle tomt valg som avbryt. Filteret Alle/Uten mappe/mappe forklarer hvorfor velger og settekasse kan ha ulike antall.

## Kodekart

| Filer | Ansvar |
| --- | --- |
| main.swift, WindowSwitcherView.swift | App, menylinje, panel, hurtigtaster og muse-/tastaturvalg |
| BoardStore.swift, Models.swift | Kort, lagring, identitet, mapper, fokus og dragkontrakt |
| Workflow*.swift, FolderViews.swift | Arkiv, mappefilter, søk, navngitt festing og mappe-UI |
| Shortcut*.swift | App-/filsnarveier, native velger, bokmerker og NSWorkspace |
| WindowAccess.swift | AX-søk, konkrete fokusoperasjoner og verifikasjon |
| WindowPin*.swift, WindowCardDrag.swift | Tittellinjedrag, snarveifesting og validerte kortdrag |
| Views.swift | Settekasse og kort |

Kildene ligger i Sources/, testene i Tests/. Nye Swift-filer må med i build.sh og relevante testkompileringer. scripts/release.py eier offentlig binærflyt. scripts/public_source.py validerer eksplisitt kildeinventar før Git/pakking.

## Data og sikkerhet

Se SECURITY.md for sikkerhetskrav og PRIVACY.md for alle lokale filer. Målsti er både i shortcuts.json og board.json.windowTitle. Ingen faktisk brukerdata i tester eller repo. Bevar originaler og stans berørte skriveruter ved innlesingsfeil. Skriv atomisk, og test transaksjoner/tilbakeføring med egne midlertidige kataloger og monitoring:false.

AX-identitet brukes innen en økt; etter restart kobles bare entydig app+tittel. Tvetydige treff skal ikke gjettes. Snarveier skal åpnes før AX-kravet og fungere uten vindustillatelse. Ingen TCC-manipulering, gjentatte tilgangsmodaler eller sikkerhetsomgåelser.

## Kontroller

```sh
zsh test.sh
python3 -m unittest discover -s Tests -p 'test_*.py'
zsh build.sh build-next
codesign --verify --strict build-next/AgentDock.app
python3 scripts/public_source.py --check
```

Alle tester skal bruke syntetiske data uten å lese faktiske arbeidsvinduer. Forhåndsvisning bruker syntetiske kort og hopper over AX/globalhotkeys, men vanlig preferansekode kan fortsatt skrive lokal UI-status. Avslutt testapper etter praktisk kontroll, og kjør én appkopi om gangen. Ikke start en ekstra normal instans for å verifisere et bygg.

Vær presis: kompilering, testmodell og registrert hurtigtast er ikke bevis på fysisk vindusbytte eller drag. Oppdater session-log.md og VALIDATION.md med faktiske resultater og åpne begrensninger. Bruk bare generelle eller syntetiske eksempler i offentlig dokumentasjon. Oppbevar eventuelle private utviklingsnotater utenfor sporede filer.

Hardened runtime gjelder også lokale bygg. Offentlige appfiler krever Developer ID Application og godkjent notarisering gjennom release.py. Private nøkler og Apple-passord hører i nøkkelringen. Ikke merk et bygg notarisert før verktøyets kontroller faktisk består.
