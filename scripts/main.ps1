Write-Output '##[group]Loading helper scripts'
Get-ChildItem -Path (Join-Path $env:GITHUB_ACTION_PATH 'scripts' 'helpers') -Filter '*.ps1' -Recurse | ForEach-Object {
    Write-Host "[$($_.FullName)]"
    . $_.FullName
}
Write-Output '##[endgroup]'

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
