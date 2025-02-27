[CmdletBinding()]
param()

$path = (Join-Path -Path $PSScriptRoot -ChildPath 'helpers')
LogGroup "Loading helper scripts from [$path]" {
    Get-ChildItem -Path $path -Filter '*.ps1' -Recurse | ForEach-Object {
        Write-Verbose "[$($_.FullName)]"
        . $_.FullName
    }
}

LogGroup 'Loading inputs' {
    Write-Verbose "Name:              [$env:PSMODULE_PUBLISH_PSMODULE_INPUT_Name]"
    Write-Verbose "GITHUB_REPOSITORY: [$env:GITHUB_REPOSITORY]"
    Write-Verbose "GITHUB_WORKSPACE:  [$env:PSMODULE_PUBLISH_PSMODULE_INPUT_WorkingDirectory]"

    $name = if ([string]::IsNullOrEmpty($env:PSMODULE_PUBLISH_PSMODULE_INPUT_Name)) {
        $env:GITHUB_REPOSITORY_NAME
    } else {
        $env:PSMODULE_PUBLISH_PSMODULE_INPUT_Name
    }
    Write-Verbose "Module name:       [$name]"
    Write-Verbose "Module path:       [$env:PSMODULE_PUBLISH_PSMODULE_INPUT_ModulePath]"
    Write-Verbose "Doc path:          [$env:PSMODULE_PUBLISH_PSMODULE_INPUT_DocsPath]"

    $params = @{
        Path      = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_WorkingDirectory
        ChildPath = "$env:PSMODULE_PUBLISH_PSMODULE_INPUT_ModulePath/$name"
    }
    $modulePath = Join-Path @params
    Write-Verbose "Module path:       [$modulePath]"
    if (-not (Test-Path -Path $modulePath)) {
        throw "Module path [$modulePath] does not exist."
    }
}

$params = @{
    Name       = $name
    ModulePath = $modulePath
    APIKey     = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_APIKey
}
Publish-PSModule @params
