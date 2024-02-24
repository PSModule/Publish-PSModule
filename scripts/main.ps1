#REQUIRES -Modules Utilities

[CmdletBinding()]
param()

Start-LogGroup 'Loading helper scripts'
Get-ChildItem -Path (Join-Path -Path $env:GITHUB_ACTION_PATH -ChildPath 'scripts' 'helpers') -Filter '*.ps1' -Recurse |
    ForEach-Object { Write-Verbose "[$($_.FullName)]"; . $_.FullName }
Stop-LogGroup

$name = [string]::IsNullOrEmpty($env:Name) ? $env:GITHUB_REPOSITORY -replace '.+/' : $env:Name

$modulePath = Join-Path -Path $env:GITHUB_WORKSPACE -ChildPath $env:ModulePath $name
if (-not (Test-Path -Path $modulePath)) {
    throw "Module path [$modulePath] does not exist."
}
$docsPath = Join-Path -Path $env:GITHUB_WORKSPACE -ChildPath $env:DocsPath $name
if (-not (Test-Path -Path $docsPath)) {
    throw "Documentation path [$docsPath] does not exist."
}

$params = @{
    Name       = $name
    ModulePath = $modulePath
    DocsPath   = $docsPath
    APIKey     = $env:APIKey
}
Publish-PSModule @params -Verbose
