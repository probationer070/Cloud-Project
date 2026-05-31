#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot

$projects = Get-ChildItem -Path $scriptDir -Directory -Filter 'project*' |
    Where-Object { Test-Path (Join-Path $_.FullName 'main.tf') }

if ($projects.Count -eq 0) {
    Write-Error "No Terraform projects found under $scriptDir"
    exit 1
}

foreach ($proj in $projects) {
    Write-Host "=== Initializing $($proj.Name) ===" -ForegroundColor Cyan
    Push-Location $proj.FullName
    try {
        terraform init -input=false
    } finally {
        Pop-Location
    }
}

Write-Host "=== All $($projects.Count) projects initialized ===" -ForegroundColor Green
