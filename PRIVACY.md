# Personvern og lokale data

AgentDock er en lokal app uten egen nettverkstrafikk, analyse, konto eller skysynkronisering. En app eller fil du starter gjennom en snarvei kan selv bruke nettverk og følge sin egen personvernpraksis.

## Tilgjengelighet

macOS Tilgjengelighet lar AgentDock lese appnavn, vindustittel, geometri og fokus, hente et valgt vindu frem og gjenopprette plasseringen etter et tittellinjedrag. Den installerte appen må få tillatelsen gjennom standard Systeminnstillinger. Tillatelsen er bredere enn operasjonene denne kildekoden utfører; installer bare bygg du stoler på.

Koden leser ikke samtale-/dokumenttekst eller passordfelt, tar ikke opptak av andre apper og logger ikke generell tastaturaktivitet. Den registrerer faste globale hurtigtaster, håndterer lokale tastetrykk mens sitt eget grensesnitt er aktivt og observerer musehendelser for vindusfesting. Utviklingsflagget `--preview` kan lagre et bilde av appens egen syntetiske visning, ikke av arbeidsvinduene.

## Datafiler

Alle fire ligger under `~/Library/Application Support/AgentDock/`:

| Fil | Innhold |
| --- | --- |
| `board.json` | Kort-ID, appnavn/-ID, opprinnelig og nåværende vindustittel, eget navn/prosjekt, pause, rekkefølge og siste besøk. Fil-/appsnarveier har også full målsti i kortets tittelfelt. |
| `folders.json` | Mappenavn, kortmedlemskap, rekkefølge og om mappen er åpen. |
| `archive.json` | Arkiverte kort-ID-er og tidspunkt. Originalkort beholdes. |
| `shortcuts.json` | Type, full målsti, macOS-filbokmerke og eventuelt appens bundle-ID. |

**Filene er JSON i klartekst**, uten appstyrt kryptering. Beskyttelsen avhenger av macOS-kontoen og filsystemets tilgangskontroll. Vindustitler og stier kan inneholde fortrolig informasjon. Filbokmerker er også private metadata. Sikkerhetskopiering og eventuell synkronisering av hjemmemappen håndteres av systemet ditt.

macOS lagrer i tillegg appinnstillinger og lokal diagnostikk under appens preferansedomene `no.magne.agentdock`. Diagnostikken inneholder status, prosess-ID, tidspunkt, antall og geometri; koden legger ikke vindustitler, filstier eller samtaleinnhold i disse statusfeltene.

## Fjerning og nullstilling

Ta ut/arkiver fjerner ikke nødvendigvis metadata fra disk: Angre og arkiv bruker de opprinnelige kortene. For full nullstilling av oversikten: avslutt appen, ta eventuell privat sikkerhetskopi og fjern de fire filene ovenfor. Dette påvirker ikke originalfilene eller arbeidsappene. Andre macOS-preferanser kan bli igjen. Trekk tilbake Tilgjengelighet i Systeminnstillinger hvis du slutter å bruke appen.

Ikke legg disse filene eller private vindusskjermbilder i GitHub-issues eller repoet. Bruk syntetiske kort ved feilrapportering.
