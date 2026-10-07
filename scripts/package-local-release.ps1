$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
$package = Join-Path $repoRoot 'release-package'
if (Test-Path $package) { throw 'Mapa release-package ze obstaja; uporabi cisto delovno mapo.' }
New-Item -ItemType Directory -Path $package | Out-Null

foreach ($folder in @('Client', 'server', 'databases', 'mssql')) {
    Copy-Item -LiteralPath $folder -Destination $package -Recurse
}
Copy-Item -LiteralPath 'LICENSE' -Destination $package
Copy-Item -LiteralPath 'README.md' -Destination (Join-Path $package 'UPSTREAM-README.md')


# Odstrani shranjeno prijavo iz izvornih uporabniskih nastavitev.
$iniPath = Join-Path $package 'Client/user/system.ini'
$ini = Get-Content -LiteralPath $iniPath -Raw
$ini = [regex]::Replace($ini, '(?ms)^\[Login\]\r?\n.*?(?=^\[|\z)', "[Login]`r`nRemember = 0`r`n")
$ini | Set-Content -LiteralPath $iniPath -Encoding utf8
foreach ($relative in @('Client/user/username.txt', 'Client/user/checkid.txt')) {
    $file = Join-Path $package $relative
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
}

foreach ($name in @('Account', 'Gate', 'Group')) {
    $project = "sources/Dotnet/Servers/$name/Corsairs.${name}Server/Corsairs.${name}Server.fsproj"
    $destination = Join-Path $package "server/${name}Server"
    & dotnet publish $project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false -p:PublishTrimmed=false -o $destination
    if ($LASTEXITCODE -ne 0) { throw "Objava streznika $name ni uspela." }
    $settingsPath = Join-Path $destination 'appsettings.json'
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    # Paket je namenjen lokalnemu igranju.
    if ($name -eq 'Account') { $settings.AccountServer.ListenAddress = '127.0.0.1' }
    if ($name -eq 'Group') { $settings.GroupServer.ListenAddress = '127.0.0.1' }
    if ($name -eq 'Gate') { $settings.Client.Address = '127.0.0.1' }
    $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding utf8
}

# Prazna stara kopija se ne uporablja; konfiguracija kaze na databases/gamedata.sqlite.
$emptyDb = Join-Path $package 'server/GameServer/gamedata.sqlite'
if ((Test-Path $emptyDb) -and (Get-Item $emptyDb).Length -eq 0) {
    Remove-Item -LiteralPath $emptyDb
}
Get-ChildItem $package -Recurse -File -Filter '*.pdb' | Remove-Item
Get-ChildItem (Join-Path $package 'databases') -File -Filter '*.bak*' | Remove-Item

$required = @(
    'Client/system/Game.exe',
    'server/GameServer/GameServer.exe',
    'server/AccountServer/Corsairs.AccountServer.exe',
    'server/GateServer/Corsairs.GateServer.exe',
    'server/GroupServer/Corsairs.GroupServer.exe',
    'databases/gamedata.sqlite',
    'databases/render.sqlite'
)
$manifest = foreach ($relative in $required) {
    $file = Join-Path $package $relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Manjka $relative" }
    if ((Get-Item -LiteralPath $file).Length -eq 0) { throw "Prazna datoteka: $relative" }
    [pscustomobject]@{ File = $relative; SHA256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash }
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $package 'checksums.json') -Encoding utf8
@(
    'Tales of Pirates - testni paket Release x64'
    "Commit: $env:GITHUB_SHA"
    ''
    'Paket vsebuje klient, igralne vsebine in strezniske programe.'
    '.NET strezniki imajo vkljuceno izvajalno okolje .NET.'
    'Lokalni SQL Server in ODBC Driver 17 se nista namescena ali nastavljena.'
    'Namestitev baze in ustvarjanje racuna se nista preverjena.'
    'Izvorne SQL skripte v mssql so prilozene za pregled, ne za slepo izvajanje.'
    'Odvisnosti programov so zapisane v build-logs/native-dependencies.txt v locenem dnevniku.'
    'Po potrebi bo treba namestiti uradne izvajalne knjiznice Visual C++ in DirectX.'
    'Uspesna sestava ne potrjuje prijave, grafike, boja ali shranjevanja.'
    'Ta paket ne vsebuje AI soigralcev ali prilagoditev napredovanja.'
) | Set-Content (Join-Path $package 'PREBERI.txt') -Encoding utf8
