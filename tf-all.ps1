#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('init', 'plan', 'apply', 'destroy')]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$Project = ''
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

# ── Project discovery ─────────────────────────────────────────────────────────
$allProjects = Get-ChildItem -Path $scriptDir -Directory -Filter 'project*' |
    Where-Object { Test-Path (Join-Path $_.FullName 'main.tf') }

if ($allProjects.Count -eq 0) {
    Write-Error "No Terraform projects found under $scriptDir"
    exit 1
}

if ($Project -ne '') {
    $targets = $allProjects | Where-Object { $_.Name -like "*$Project*" }
    if ($targets.Count -eq 0) {
        Write-Error "No project matching '$Project'. Available: $($allProjects.Name -join ', ')"
        exit 1
    }
} else {
    $targets = $allProjects
}

# ── Confirmation gate for destructive commands ────────────────────────────────
if ($Command -in 'apply', 'destroy' -and $Project -eq '') {
    Write-Host ""
    Write-Host "  Command : $Command" -ForegroundColor Yellow
    Write-Host "  Targets : $($targets.Name -join ', ')" -ForegroundColor Yellow
    Write-Host ""
    $answer = Read-Host "  This will $Command ALL projects. Type 'yes' to continue"
    if ($answer -ne 'yes') { Write-Host "Aborted." -ForegroundColor Red; exit 1 }
    Write-Host ""
}

# ── Per-project result tracking ───────────────────────────────────────────────
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($proj in $targets) {
    Write-Host "=== $Command : $($proj.Name) ===" -ForegroundColor Cyan

    $capturedLines = [System.Collections.Generic.List[string]]::new()
    $exitCode = 0

    Push-Location $proj.FullName
    try {
        & terraform $Command -input=false 2>&1 | ForEach-Object {
            $line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { "$_" }
            Write-Host $line
            $capturedLines.Add($line)
        }
        $exitCode = $LASTEXITCODE
    } catch {
        $capturedLines.Add("EXCEPTION: $_")
        $exitCode = 1
    } finally {
        Pop-Location
    }

    # Parse result lines
    $planLine    = $capturedLines | Where-Object { $_ -match 'Plan:\s+\d+ to add' } | Select-Object -Last 1
    $errorLines  = $capturedLines | Where-Object { $_ -match '\bError:' }
    $warnLines   = $capturedLines | Where-Object { $_ -match '(Warning:|warning:)' }
    $applyLine   = $capturedLines | Where-Object { $_ -match 'Apply complete!' }   | Select-Object -Last 1
    $destroyLine = $capturedLines | Where-Object { $_ -match 'Destroy complete!' } | Select-Object -Last 1

    # Build summary string
    $status = 'OK'
    $summary = 'Completed'

    if ($exitCode -ne 0 -or $errorLines.Count -gt 0) {
        $status = 'ERROR'
        $firstError = ($errorLines | Select-Object -First 1) -replace '^\s+', '' -replace '\s+', ' '
        if (-not $firstError) { $firstError = 'terraform exited with code ' + $exitCode }

        # Extract file:line reference if present
        $refLine = $capturedLines | Where-Object { $_ -match 'on .+\.tf line \d+' } | Select-Object -First 1
        $fileRef = ''
        if ($refLine -match 'on (.+\.tf) line (\d+)') {
            $fileRef = ' (' + $Matches[1] + ':' + $Matches[2] + ')'
        }
        $summary = $firstError + $fileRef
    } elseif ($planLine) {
        $summary = ($planLine -replace '.*?(Plan:.+)', '$1').Trim()
        if ($warnLines.Count -gt 0) { $status = 'WARN' }
    } elseif ($applyLine) {
        $summary = $applyLine.Trim()
        if ($warnLines.Count -gt 0) { $status = 'WARN' }
    } elseif ($destroyLine) {
        $summary = $destroyLine.Trim()
        if ($warnLines.Count -gt 0) { $status = 'WARN' }
    } elseif ($Command -eq 'init') {
        $summary = if ($exitCode -eq 0) { 'Initialized successfully' } else { 'Init failed (no detail)' }
        if ($exitCode -ne 0) { $status = 'ERROR' }
    }

    $results.Add([PSCustomObject]@{
        Name     = $proj.Name
        Status   = $status
        Summary  = $summary
        Warnings = $warnLines.Count
    })

    Write-Host ""
}

# ── Final summary table ───────────────────────────────────────────────────────
$bar     = '-' * 72
$okCnt   = ($results | Where-Object { $_.Status -eq 'OK'    }).Count
$warnCnt = ($results | Where-Object { $_.Status -eq 'WARN'  }).Count
$errCnt  = ($results | Where-Object { $_.Status -eq 'ERROR' }).Count
$total   = $results.Count

Write-Host $bar
Write-Host ("  {0} SUMMARY  —  {1} project(s)" -f $Command.ToUpper(), $total)
Write-Host $bar

foreach ($r in $results) {
    $icon  = switch ($r.Status) { 'OK' { '[OK]  ' } 'WARN' { '[WARN]' } 'ERROR' { '[ERR] ' } }
    $color = switch ($r.Status) { 'OK' { 'Green' }  'WARN' { 'Yellow' } 'ERROR' { 'Red'    } }
    $wTag  = if ($r.Warnings -gt 0) { "  ($($r.Warnings) warning(s))" } else { '' }
    $name  = $r.Name.PadRight(38)
    Write-Host ("  {0}  {1}  {2}{3}" -f $icon, $name, $r.Summary, $wTag) -ForegroundColor $color
}

Write-Host $bar
$totLine = "  Total: $total  |  OK: $okCnt  |  ERROR: $errCnt"
if ($warnCnt -gt 0) { $totLine += "  |  WARN: $warnCnt" }
Write-Host $totLine
Write-Host $bar

if ($errCnt -gt 0) { exit 1 }
