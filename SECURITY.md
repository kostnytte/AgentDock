# Sikkerhet

## Omfang og forventninger

AgentDock er en lokal enkeltbrukerapp for macOS, uten nettverksendepunkter eller eksterne pakkeavhengigheter. Den kjører med brukerens rettigheter og kan få Tilgjengelighet-tilgang. Kjør én appkopi om gangen. Les [PRIVACY.md](PRIVACY.md) før du gir tilgang.

Fremtidige endringer skal bevare disse grensene:

- Vindustitler, pasteboard-data og andre appers metadata er upålitelig input. De skal vises som tekst og aldri tolkes som kode, kommando eller filbane.
- AX-operasjoner skal kreve vanlig macOS-tillatelse og være begrenset til dokumenterte vindusoperasjoner. Ingen innlesing av samtaleinnhold, generell tastelogg, skjermopptak eller endring av TCC-databasen.
- Åpning av app-/filsnarveier skjer etter et brukerbesøk og via NSWorkspace. Ikke introduser shell, automatisk kjøring ved innlasting eller nedlasting av kode.
- Bevar konkrete vindusidentiteter innen en økt. Ved omstart skal tvetydige treff forbli utilgjengelige fremfor å gjette.
- Private metadata skal forbli lokale. Bevar skadede filer og eksisterende data når lesing eller skriving feiler. Et kortdrag skal knyttes til en aktiv operasjon.
- Distribusjon må bruke Developer ID Application, hardened runtime, sikker timestamp, godkjent Apple-notarisering og validert påheftet ticket. Lokale ad hoc-bygg er utviklingsbygg.
- Ingen private nøkler, passord, faktiske kortdata, skjermbilder av arbeid eller private logger i Git.

En prosess som allerede har samme brukers filtilgang kan lese/endre lokale metadata og valgte mål. AgentDock utgjør ikke en isolasjonsgrense mot et allerede kompromittert brukermiljø. Dette opphever ikke behovet for å vurdere reelle rettighetseskaleringer og uventet myndighet på tvers av appgrenser.

## Rapportering

Bruk GitHubs **Report a vulnerability** hvis denne muligheten er aktivert i prosjektet. Ikke publiser hemmeligheter, personopplysninger eller en operativ utnyttelsesoppskrift i en åpen issue. Hvis privat rapportering ikke er tilgjengelig, be om en privat kontaktkanal i en issue uten tekniske eller sensitive detaljer. Det finnes foreløpig ingen lovet responstid eller ekstern sikkerhetssertifisering.

## Utført gjennomgang

10. november 2026: statisk gjennomgang av 31 nåværende kilde-, test-, konfigurasjons- og dokumentasjonsfiler i 0.11. Ingen rapporterbare sårbarheter eller innebygde hemmeligheter ble funnet. Genererte binærer, eldre sikkerhetskopier, den separate gamle oppdateringsinstalleren og faktisk brukerdata var utelatt. Gjennomgangen er ingen garanti for senere endringer eller utgivelser.
