# Run only on the disposable GitHub Actions Windows runner.
#requires -Version 5.1
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Ta test je samo za zacasni CI racunalnik.' }
$root = Split-Path -Parent $PSScriptRoot
$setup = Join-Path $root 'local/Local-Setup.ps1'
$tokens = $null; $parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($setup, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$localdb = Get-ChildItem 'C:/Program Files/Microsoft SQL Server/*/Tools/Binn/SqlLocalDB.exe' | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $localdb) { throw 'SQL LocalDB ni namescen na runnerju.' }
& $localdb.FullName create TopSetupCI -s
if ($LASTEXITCODE -ne 0) { throw 'Ustvarjanje izolirane instance ni uspelo.' }
$instance = '(localdb)\TopSetupCI'
& $setup -Action Initialize -SqlServer $instance
$hash = '327E7E3821F5F6D33C090137F979BF48EE62E9051C1610E1D6468ECB3C67A124'
& $setup -Action Account -SqlServer $instance -Username setup_test -PasswordHash $hash
$refused = $false
try { & $setup -Action Initialize -SqlServer $instance } catch {
    if ($_.Exception.Message -notlike '*ze obstaja*') { throw }
    $refused = $true
}
if (-not $refused) { throw 'Initialize ni zavrnil obstojecih baz.' }
$refused = $false
try { & $setup -Action Account -SqlServer $instance -Username setup_test -PasswordHash ('A' * 64) } catch {
    if ($_.Exception.Message -notlike '*Racun ze obstaja*') { throw }
    $refused = $true
}
if (-not $refused) { throw 'Podvojen racun ni bil zavrnjen.' }
Add-Type -AssemblyName System.Data
$connection = New-Object Data.SqlClient.SqlConnection "Server=$instance;Database=master;Integrated Security=True"
try {
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = @'
IF (SELECT COUNT(*) FROM AccountServer.dbo.account_login) <> 1 THROW 51000, 'Account count', 1;
IF (SELECT COUNT(*) FROM GameDB.dbo.account) <> 1 THROW 51000, 'Game account count', 1;
IF NOT EXISTS (SELECT 1 FROM AccountServer.dbo.account_login a JOIN GameDB.dbo.account g ON a.id=g.ato_id
 WHERE a.name='setup_test' AND g.ato_nome=a.name AND g.jmes=0 AND a.login_status=0
 AND a.password='327E7E3821F5F6D33C090137F979BF48EE62E9051C1610E1D6468ECB3C67A124')
 THROW 51000, 'Account linkage or unchanged password', 1;
IF (SELECT COUNT(*) FROM GameDB.dbo.guild) <> 199 THROW 51000, 'Guild seed', 1;
IF OBJECT_ID('GameDB.dbo.player_map_masks') IS NULL THROW 51000, 'Map mask migration', 1;
'@
    [void]$command.ExecuteNonQuery()
} finally { $connection.Dispose() }
Write-Host 'PASS: shema, migracija, racun, povezava ID in zavrnitev prepisovanja.'
