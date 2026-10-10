$ErrorActionPreference = 'Stop'
$fxc = Get-ChildItem "${env:ProgramFiles(x86)}/Windows Kits/10/bin/*/x64/fxc.exe" | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $fxc) { throw 'Windows SDK shader compiler fxc.exe is missing.' }
$reportDir = 'build-logs/shaders'
New-Item -ItemType Directory -Force $reportDir | Out-Null
function Test-Shader {
    param([string]$Name, [string]$File, [string[]]$Defines = @())
    $arguments = @('/nologo', '/T', 'vs_2_0', '/E', 'main', '/Fo', "$reportDir/$Name.bin", '/Fc', "$reportDir/$Name.asm")
    foreach ($define in $Defines) { $arguments += @('/D', $define) }
    $arguments += "Client/shader/dx9/$File"
    & $fxc.FullName @arguments
    if ($LASTEXITCODE -ne 0) { throw "Vertex shader failed: $Name" }
    Write-Host "PASS vs_2_0 $Name"
}
foreach ($weights in 0..3) {
    Test-Shader -Name "static-skin-$weights" -File 'static_skin.hlsl' -Defines @("NUM_EXPLICIT_WEIGHTS=$weights")
}
foreach ($weights in 1..2) {
    foreach ($mode in 1..3) {
        Test-Shader -Name "skinmesh-$weights-$mode" -File 'skinmesh.hlsl' -Defines @("NUM_SKIN_WEIGHTS=$weights", "TT_MODE=$mode")
    }
}
Test-Shader -Name 'pndt0-ld' -File 'vs_pndt0.hlsl'
Test-Shader -Name 'pndt0' -File 'vs_pndt0.hlsl' -Defines @('NO_LIGHTING=1')
Test-Shader -Name 'pndt0-ld-tt0' -File 'vs_pndt0.hlsl' -Defines @('USE_TEX_TRANSFORM=1')
Test-Shader -Name 'pndt0-tt0' -File 'vs_pndt0.hlsl' -Defines @('NO_LIGHTING=1', 'USE_TEX_TRANSFORM=1')
Test-Shader -Name 'pnt0-ld' -File 'vs_pndt0.hlsl' -Defines @('NO_DIFFUSE=1')
Test-Shader -Name 'pnt0-ld-tt0' -File 'vs_pndt0.hlsl' -Defines @('NO_DIFFUSE=1', 'USE_TEX_TRANSFORM=1')
Test-Shader -Name 'pnt0-tt0' -File 'vs_pndt0.hlsl' -Defines @('NO_LIGHTING=1', 'NO_DIFFUSE=1', 'USE_TEX_TRANSFORM=1')
foreach ($name in @('eff1', 'eff2', 'eff3', 'eff4', 'shadeeff', 'minimap')) {
    Test-Shader -Name $name -File "$name.hlsl"
}
Write-Host 'PASS: all 23 runtime vertex shader variants compile for the fixed-function pixel pipeline.'
