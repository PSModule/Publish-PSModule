#REQUIRES -Modules Utilities

[CmdletBinding()]
param()

Start-LogGroup 'Loading helper scripts'
Get-ChildItem -Path (Join-Path -Path $env:GITHUB_ACTION_PATH -ChildPath 'scripts' 'helpers') -Filter '*.ps1' -Recurse |
    ForEach-Object { Write-Verbose "[$($_.FullName)]"; . $_.FullName }
Stop-LogGroup

Write-Verbose "Name:              [$env:Name]"
Write-Verbose "GITHUB_REPOSITORY: [$env:GITHUB_REPOSITORY]"
Write-Verbose "GITHUB_WORKSPACE:  [$env:GITHUB_WORKSPACE]"

$name = [string]::IsNullOrEmpty($env:Name) ? $env:GITHUB_REPOSITORY -replace '.+/' : $env:Name
Write-Verbose "Module name:       [$name]"
Write-Verbose "Module path:       [$env:ModulePath]"
Write-Verbose "Doc path:          [$env:DocPath]"

$modulePath = Join-Path -Path $env:GITHUB_WORKSPACE -ChildPath $env:ModulePath $name
Write-Verbose "Module path:       [$modulePath]"
if (-not (Test-Path -Path $modulePath)) {
    throw "Module path [$modulePath] does not exist."
}
$docPath = Join-Path -Path $env:GITHUB_WORKSPACE -ChildPath $env:DocPath $name
Write-Verbose "Docs path:         [$docPath]"
if (-not (Test-Path -Path $docPath)) {
    throw "Documentation path [$docPath] does not exist."
}

$params = @{
    Name       = $name
    ModulePath = $modulePath
    DocsPath   = $docPath
    APIKey     = $env:APIKey
}
Publish-PSModule @params -Verbose
