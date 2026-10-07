#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Check','Initialize','Account','Start','Client')]
    [string]$Action = 'Check',
    [string]$SqlServer = 'localhost',
    [string]$Username,
    [string]$PasswordHash
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Data

function Open-Database([string]$database = 'master') {
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source'] = $SqlServer
    $builder['Initial Catalog'] = $database
    $builder['Integrated Security'] = $true
    $builder['TrustServerCertificate'] = $true
    $builder['Connect Timeout'] = 10
    $connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
    $connection.Open()
    return $connection
}

function Invoke-SqlFile($connection, [string]$relative) {
    $sql = [IO.File]::ReadAllText((Join-Path $root $relative))
    $number = 0
    foreach ($batch in [regex]::Split($sql, '(?im)^\s*GO\s*\r?$')) {
        $number++
        if ([string]::IsNullOrWhiteSpace($batch)) { continue }
        $command = $connection.CreateCommand()
        try {
            $command.CommandTimeout = 120
            $command.CommandText = $batch
            [void]$command.ExecuteNonQuery()
        } catch { throw "Napaka v $relative, sklop ${number}: $($_.Exception.Message). Bazi sta lahko delno pripravljeni; ne brisi ju na slepo." }
        finally { $command.Dispose() }
    }
}

function Assert-Schema {
    $connection = Open-Database
    try {
        $command = $connection.CreateCommand()
        $command.CommandText = @'
SELECT CASE WHEN OBJECT_ID('AccountServer.dbo.account_login') IS NOT NULL
 AND OBJECT_ID('GameDB.dbo.character') IS NOT NULL
 AND OBJECT_ID('GameDB.dbo.player_map_masks') IS NOT NULL
 AND COL_LENGTH('GameDB.dbo.guild', 'banklog') IS NOT NULL THEN 1 ELSE 0 END
'@
        if ($command.ExecuteScalar() -ne 1) { throw 'Bazi ali obvezne tabele manjkajo. Najprej izvedi Initialize.' }
    } finally { $connection.Dispose() }
}

function Test-Port([int]$port) {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect('127.0.0.1', $port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne(300)) { return $false }
        $client.EndConnect($pending)
        return $true
    } catch { return $false } finally { $client.Dispose() }
}

function Wait-Port($process, [int]$port) {
    $limit = [DateTime]::UtcNow.AddSeconds(45)
    do {
        $process.Refresh()
        if ($process.HasExited) { throw "Streznik se je zaprl. Preveri njegovo okno in dnevnike. Vrata: $port" }
        if (Test-Port $port) { return }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $limit)
    throw "Streznik ni odprl vrat $port. Preveri dnevnike; ne zaganjaj druge kopije."
}

switch ($Action) {
    'Initialize' {
        $files = @('mssql/[0]AccountServer.sql', 'mssql/[1]GameDB.sql',
            'databases/migrate_player_map_masks.sql', 'local/Complete-Schema.sql')
        foreach ($file in $files) {
            if (-not (Test-Path -LiteralPath (Join-Path $root $file))) { throw "Manjka $file" }
        }
        $connection = Open-Database
        try {
            $command = $connection.CreateCommand()
            $command.CommandText = "SELECT COUNT(*) FROM sys.databases WHERE name IN ('AccountServer','GameDB')"
            if ($command.ExecuteScalar() -ne 0) { throw 'AccountServer ali GameDB ze obstaja. Ustavitev brez sprememb; obstojecega napredka ne prepisujemo.' }
            foreach ($file in $files) { Invoke-SqlFile $connection $file }
        } finally { $connection.Dispose() }
        Assert-Schema
        Write-Host 'Bazi sta pripravljeni. Naslednji korak: ustvari racun.'
    }
    'Account' {
        Assert-Schema
        if (-not $Username) { $Username = Read-Host 'Uporabnisko ime (3-20 crk, stevilk ali _)' }
        if ($Username -cnotmatch '^[A-Za-z0-9_]{3,20}$') { throw 'Neveljavno uporabnisko ime.' }
        if (-not $PasswordHash) {
            $python = Get-Command py.exe -ErrorAction SilentlyContinue
            $prefix = @('-3')
            if (-not $python) { $python = Get-Command python.exe -ErrorAction SilentlyContinue; $prefix = @() }
            if (-not $python) { throw 'Za ustvarjanje racuna namesti Python 3 (python.org), nato odpri novo okno.' }
            $secret = Read-Host 'Novo geslo za igro (8-20 znakov ASCII)' -AsSecureString
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
            try {
                $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
                if ($plain -cnotmatch '^[\x21-\x7E]{8,20}$') { throw 'Uporabi 8-20 znakov brez presledkov in sumnikov.' }
                $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plain))
                $PasswordHash = $encoded | & $python.Source @prefix -c 'import sys,base64,hashlib; print(hashlib.blake2s(base64.b64decode(sys.stdin.read().strip(),validate=True)).hexdigest().upper())'
                if ($LASTEXITCODE -ne 0 -or $PasswordHash -cnotmatch '^[A-F0-9]{64}$') { throw 'Izracun gesla ni uspel. Preveri Python 3.' }
            } finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
                $plain = $null; $encoded = $null; $secret.Dispose()
            }
        }
        if ($PasswordHash -cnotmatch '^[A-F0-9]{64}
BEGIN TRANSACTION;
IF EXISTS (SELECT 1 FROM AccountServer.dbo.account_login WITH (UPDLOCK,HOLDLOCK) WHERE name=@name)
    THROW 51000, 'Racun ze obstaja; gesla in napredka ne spreminjamo.', 1;
INSERT AccountServer.dbo.account_login (name,password,salt,ban)
VALUES (@name,@hash,'',0);
DECLARE @id int = CONVERT(int,SCOPE_IDENTITY());
IF EXISTS (SELECT 1 FROM GameDB.dbo.account WHERE ato_id=@id OR ato_nome=@name)
    THROW 51001, 'Obstaja neujemajoc igralni racun. Potreben je pregled.', 1;
INSERT GameDB.dbo.account (ato_id,ato_nome,jmes,ator_ids)
VALUES (@id,@name,0,'0');
COMMIT;
SELECT @id;
'@
            [void]$command.Parameters.Add('@name',[Data.SqlDbType]::VarChar,50)
            $command.Parameters['@name'].Value = $Username
            [void]$command.Parameters.Add('@hash',[Data.SqlDbType]::VarChar,255)
            $command.Parameters['@hash'].Value = $PasswordHash
            $id = $command.ExecuteScalar()
            Write-Host "Racun $Username je ustvarjen (ID $id). Lik ustvari v igri."
        } finally { $connection.Dispose(); $PasswordHash = $null }
    }
    'Check' {
        Assert-Schema
        $odbc = New-Object Data.Odbc.OdbcConnection "Driver={ODBC Driver 17 for SQL Server};Server=$SqlServer;Database=GameDB;Trusted_Connection=Yes"
        try { $odbc.Open() } finally { $odbc.Dispose() }
        Write-Host 'Povezava z bazama, osnovna shema in ODBC 17 delujejo.'
    }
    'Start' {
        if ($SqlServer -ne 'localhost') { throw 'Ta zaganjalnik uporablja privzeto lokalno instanco SQL Server (localhost).' }
        & $PSCommandPath -Action Check
        $names = @('Account','Group','Gate')
        $ports = @(1978,1975,1973)
        $processNames = @('Corsairs.AccountServer','Corsairs.GroupServer','Corsairs.GateServer','GameServer')
        if (Get-Process -Name $processNames -ErrorAction SilentlyContinue) { throw 'Streznik ze tece. Najprej preveri njegova okna.' }
        foreach ($port in @(1978,1975,1973,1971,15000,15001,15002)) {
            if (Test-Port $port) { throw "Vrata $port so ze zasedena." }
        }
        foreach ($name in $names) {
            if (-not (Test-Path -LiteralPath (Join-Path $root "server/${name}Server/Corsairs.${name}Server.exe"))) { throw "Manjka ${name}Server." }
        }
        $gameDir = Join-Path $root 'server/GameServer'
        if (-not (Test-Path -LiteralPath (Join-Path $gameDir 'GameServer.exe'))) { throw 'Manjka GameServer.exe.' }
        for ($i=0; $i -lt $names.Count; $i++) {
            $name = $names[$i]
            $directory = Join-Path $root "server/${name}Server"
            $process = Start-Process -FilePath (Join-Path $directory "Corsairs.${name}Server.exe") -WorkingDirectory $directory -PassThru
            Wait-Port $process $ports[$i]
        }
        Wait-Port $process 1971
        [void](Start-Process -FilePath (Join-Path $gameDir 'GameServer.exe') -ArgumentList 'GameServer00.cfg' -WorkingDirectory $gameDir -PassThru)
        Write-Host 'Procesi so zagnani. Pocakaj, da GameServer nalozi zemljevide in se poveze z Gate. Nato zazeni igro.'
        Write-Host 'Odprta vrata se niso dokaz uspesne prijave. Ob napaki preveri konzole; procesov ne zaganjaj ponovno.'
    }
    'Client' {
        if (-not (Test-Port 1973)) { throw 'Lokalni GateServer se ne poslusa na vratih 1973. Najprej zazeni streznike.' }
        $clientDir = Join-Path $root 'Client'
        Start-Process -FilePath (Join-Path $clientDir 'system/Game.exe') -ArgumentList 'pKcfT0PcaX' -WorkingDirectory $clientDir
    }
}
) { throw 'Neveljaven BLAKE2s hash gesla.' }
        $connection = Open-Database
        try {
            $command = $connection.CreateCommand()
            $command.CommandText = @'
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF EXISTS (SELECT 1 FROM AccountServer.dbo.account_login WITH (UPDLOCK,HOLDLOCK) WHERE name=@name)
    THROW 51000, 'Racun ze obstaja; gesla in napredka ne spreminjamo.', 1;
INSERT AccountServer.dbo.account_login (name,password,salt,ban)
VALUES (@name,@hash,'',0);
DECLARE @id int = CONVERT(int,SCOPE_IDENTITY());
IF EXISTS (SELECT 1 FROM GameDB.dbo.account WHERE ato_id=@id OR ato_nome=@name)
    THROW 51001, 'Obstaja neujemajoc igralni racun. Potreben je pregled.', 1;
INSERT GameDB.dbo.account (ato_id,ato_nome,jmes,ator_ids)
VALUES (@id,@name,0,'0');
COMMIT;
SELECT @id;
'@
            [void]$command.Parameters.Add('@name',[Data.SqlDbType]::VarChar,50)
            $command.Parameters['@name'].Value = $Username
            [void]$command.Parameters.Add('@hash',[Data.SqlDbType]::VarChar,255)
            $command.Parameters['@hash'].Value = $PasswordHash
            $id = $command.ExecuteScalar()
            Write-Host "Racun $Username je ustvarjen (ID $id). Lik ustvari v igri."
        } finally { $connection.Dispose(); $PasswordHash = $null }
    }
    'Check' {
        Assert-Schema
        $odbc = New-Object Data.Odbc.OdbcConnection "Driver={ODBC Driver 17 for SQL Server};Server=$SqlServer;Database=GameDB;Trusted_Connection=Yes"
        try { $odbc.Open() } finally { $odbc.Dispose() }
        Write-Host 'Povezava z bazama, osnovna shema in ODBC 17 delujejo.'
    }
    'Start' {
        if ($SqlServer -ne 'localhost') { throw 'Ta zaganjalnik uporablja privzeto lokalno instanco SQL Server (localhost).' }
        & $PSCommandPath -Action Check
        $names = @('Account','Group','Gate')
        $ports = @(1978,1975,1973)
        $processNames = @('Corsairs.AccountServer','Corsairs.GroupServer','Corsairs.GateServer','GameServer')
        if (Get-Process -Name $processNames -ErrorAction SilentlyContinue) { throw 'Streznik ze tece. Najprej preveri njegova okna.' }
        foreach ($port in @(1978,1975,1973,1971,15000,15001,15002)) {
            if (Test-Port $port) { throw "Vrata $port so ze zasedena." }
        }
        foreach ($name in $names) {
            if (-not (Test-Path -LiteralPath (Join-Path $root "server/${name}Server/Corsairs.${name}Server.exe"))) { throw "Manjka ${name}Server." }
        }
        $gameDir = Join-Path $root 'server/GameServer'
        if (-not (Test-Path -LiteralPath (Join-Path $gameDir 'GameServer.exe'))) { throw 'Manjka GameServer.exe.' }
        for ($i=0; $i -lt $names.Count; $i++) {
            $name = $names[$i]
            $directory = Join-Path $root "server/${name}Server"
            $process = Start-Process -FilePath (Join-Path $directory "Corsairs.${name}Server.exe") -WorkingDirectory $directory -PassThru
            Wait-Port $process $ports[$i]
        }
        Wait-Port $process 1971
        [void](Start-Process -FilePath (Join-Path $gameDir 'GameServer.exe') -ArgumentList 'GameServer00.cfg' -WorkingDirectory $gameDir -PassThru)
        Write-Host 'Procesi so zagnani. Pocakaj, da GameServer nalozi zemljevide in se poveze z Gate. Nato zazeni igro.'
        Write-Host 'Odprta vrata se niso dokaz uspesne prijave. Ob napaki preveri konzole; procesov ne zaganjaj ponovno.'
    }
    'Client' {
        if (-not (Test-Port 1973)) { throw 'Lokalni GateServer se ne poslusa na vratih 1973. Najprej zazeni streznike.' }
        $clientDir = Join-Path $root 'Client'
        Start-Process -FilePath (Join-Path $clientDir 'system/Game.exe') -ArgumentList 'pKcfT0PcaX' -WorkingDirectory $clientDir
    }
}
