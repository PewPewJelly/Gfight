param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [switch]$SkipNetwork
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $projectRoot '.godot/test-output'
New-Item -ItemType Directory -Force $outputRoot | Out-Null
$originalAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $projectRoot '.godot/test_userdata'
    New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
    foreach ($testScript in @('combat_test.gd', 'gameplay_test.gd', 'ui_flow_test.gd')) {
        $testOutput = & $GodotPath --headless --path $projectRoot --script "res://tests/$testScript" 2>&1
        $testExitCode = $LASTEXITCODE
        $testOutput | Write-Output
        if ($testExitCode -ne 0 -or ($testOutput | Select-String -Pattern 'SCRIPT ERROR:|ERROR:')) { throw "$testScript failed ($testExitCode)" }
    }
    if (-not $SkipNetwork) {
        $hostLog = Join-Path $outputRoot 'host.log'
        $hostErrors = Join-Path $outputRoot 'host.err'
        $clientLog = Join-Path $outputRoot 'client.log'
        $clientErrors = Join-Path $outputRoot 'client.err'
        $hostArguments = @('--headless', '--path', ('"{0}"' -f $projectRoot), '--script', 'res://tests/network_peer.gd', '--', 'host')
        $clientArguments = @('--headless', '--path', ('"{0}"' -f $projectRoot), '--script', 'res://tests/network_peer.gd', '--', 'client')
        $hostProcess = Start-Process -FilePath $GodotPath -ArgumentList $hostArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $hostLog -RedirectStandardError $hostErrors
        Start-Sleep -Seconds 1
        $clientProcess = Start-Process -FilePath $GodotPath -ArgumentList $clientArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $clientLog -RedirectStandardError $clientErrors
        $hostFinished = $hostProcess.WaitForExit(30000)
        $clientFinished = $clientProcess.WaitForExit(3000)
        Get-Content -LiteralPath $hostLog, $hostErrors, $clientLog, $clientErrors
        if (-not $hostFinished -or -not $clientFinished) {
            # Stop only these test processes, never another Godot instance.
            if (-not $hostProcess.HasExited) { $hostProcess.Kill() }
            if (-not $clientProcess.HasExited) { $clientProcess.Kill() }
            throw 'Network checks timed out.'
        }
        if ($hostProcess.ExitCode -ne 0 -or $clientProcess.ExitCode -ne 0 -or (Get-Item $hostErrors).Length -gt 0 -or (Get-Item $clientErrors).Length -gt 0) {
            throw 'Network checks failed; see .godot/test-output.'
        }
    }
    Write-Output 'All requested checks passed.'
} finally {
    $env:APPDATA = $originalAppData
}
