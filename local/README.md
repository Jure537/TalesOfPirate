# Prvi lokalni zagon na Windows 10 x64

To je testni paket. Uspesen build in test baze se ne dokazujeta, da deluje prijava ali igranje.

## 1. Namestitev (enkrat)

Razpakiraj celoten novi paket v npr. `C:\Games\TalesOfPirates`. Ne premikaj samo Game.exe: Client, server, databases in local morajo ostati skupaj.

- Namesti **SQL Server 2022 Express, Database Engine**, prek moznosti **Custom**. Pri Instance Configuration izberi **Default instance (MSSQLSERVER)**. Trenutni GameServer zahteva `localhost`; privzeti Basic namesti imenovano instanco SQLEXPRESS, ki brez dodatnih sprememb ne ustreza.
- Izberi Windows authentication in **Add Current User** pri skrbnikih SQL. Skripte in igro zaganjaj s tem Windows uporabnikom. SQL gesla `sa` ne potrebujemo.
- Namesti **Microsoft ODBC Driver 17 for SQL Server, x64**. Driver 18 sam ne nadomesti imena Driver 17, ki ga zahteva koda.
- Za enkratno ustvarjanje racuna namesti **Python 3** z uradne strani python.org, vkljuci launcher `py` oziroma dodaj Python v PATH. Za vsakodnevno igranje ga ne potrebujes.

Uradni viri:
- https://learn.microsoft.com/en-us/sql/sql-server/install/hardware-and-software-requirements-for-installing-sql-server-2022
- https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server (izberi razdelek 17)
- https://www.python.org/downloads/windows/

Ce SQL Server ze uporabljas za drugo delo ali ze obstajata bazi AccountServer/GameDB, se ustavi za pregled obstojece namestitve. Skripta ne brise in ne prepisuje obstojecih baz. SSMS je izbiren; za te skripte ni potreben.

## 2. Priprava (enkrat)

V mapi `local` dvoklikni po vrsti:

1. `01-Pripravi-bazo.cmd` - ustvari AccountServer in GameDB, doda migracijo zemljevidov ter zacetne vrstice za guild.
2. `02-Ustvari-racun.cmd` - vpisi svoje uporabnisko ime in novo geslo za igro. Geslo ni vidno med tipkanjem. Uporabi 8-20 znakov ASCII brez presledkov. Racun je obicajen igralec, brez GM pravic.
3. `03-Preveri.cmd` - preveri bazi in povezavo z ODBC 17.

Geslo se pretvori v BLAKE2s z velikimi crkami, tako kot v klientu. Ne uporablja se star primer `admin` iz mssql. Skripta ne izpisuje gesla ali hasha in ju ne shranjuje v datoteke. Windows gesla ali gesla od drugih storitev ne uporabljaj za igro.

Ce priprava vmes odpove, shrani sporocilo napake. Lahko je nastala delna baza; ponovno izvajanje namenoma ne nadaljuje in je ne brise. Potreben je pregled napake.

## 3. Vsakodnevni zagon

1. `04-Zazeni-streznike.cmd` - odpre Account, Group, Gate in GameServer. Pocaka na vrata prvih treh; GameServer mora nato se naloziti zemljevide in se povezati.
2. Pusti strezniska okna odprta. Ce se okno zapre ali izpise napako, shrani posnetek oziroma dnevnik. Zaganjalnik ob delni napaki ne ustavlja drugih procesov in ne zacne druge kopije.
3. `05-Zazeni-igro.cmd` - odpre klient z ustrezno delovno mapo in zagonskim argumentom.
4. Izberi lokalni streznik v regiji **Local**, prijavi se in za prvi preizkus ustvari lik v **Argent City**.
5. Preizkusi premik, boj, odjavo in ponovno prijavo. Nato izstopi iz igre, ustavi streznike in ponovi zagon ter preveri shranjen napredek.

Pri ustavljanju najprej zapusti igro. .NET streznike ustavi s Ctrl+C v njihovih oknih. Za GameServer je treba pri prvem preizkusu preveriti njegov varen izhod in shranjevanje; prisilno koncanje procesa ni preverjen nacin shranjevanja. Zaganjalnik zato nima gumba, ki bi na silo ustavil vse procese.

Vrata strezniskih programov v tem paketu so namenjena samo lokalnemu racunalniku. Za igranje ne odpiraj vrat usmerjevalnika. Paket ne konfigurira Windows pozarnega zidu.

## Ce se kaj zatakne

- Napaka SQL povezave: preveri storitev SQL Server (MSSQLSERVER), Windows uporabnika in izbiro privzete instance.
- Manjka ODBC Driver 17: namesti x64 razlicico 17, tudi ce ze imas 18.
- Manjka DLL: poslji tocno ime. Namestitev dodatnega izvajalnega okolja bo odvisna od sporocila; ne prenasaj posameznih DLL z nakljucnih strani.
- Prijava ne uspe: shrani dnevnike Account/Group/Gate in GameServer. Uspesno odprta vrata ne potrdijo povezave med vsemi procesi.
- Napredek je v SQL Serverju, ne v ZIP-u z igro. Kopija igralne mape ni varnostna kopija likov.

Skripte so namenjene **Windows PowerShell 5.1 x64**, ki je del Windows 10. `.cmd` uporabi dovoljenje za izvedbo samo za svoj proces; ne spreminja trajne nastavitve sistema.
