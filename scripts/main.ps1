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

    [pscustomobject]@{
        Name              = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_Name
        WorkingDirectory  = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_WorkingDirectory
        ModulePath        = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_ModulePath
        DocsPath          = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_DocsPath
        APIKey            = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_APIKey
        GITHUB_REPOSITORY = $env:GITHUB_REPOSITORY
    } | Format-List


    $name = if ([string]::IsNullOrEmpty($env:PSMODULE_PUBLISH_PSMODULE_INPUT_Name)) {
        $env:GITHUB_REPOSITORY_NAME
    } else {
        $env:PSMODULE_PUBLISH_PSMODULE_INPUT_Name
    }
    $modulePath = Resolve-Path -Path "$env:PSMODULE_PUBLISH_PSMODULE_INPUT_WorkingDirectory/$env:PSMODULE_PUBLISH_PSMODULE_INPUT_ModulePath/$name" |
        Select-Object -ExpandProperty Path
    Write-Verbose "Resolved path:     [$modulePath]"

    [pscustomobject]@{
        Name              = $name
        WorkingDirectory  = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_WorkingDirectory
        ModulePath        = $modulePath
        DocsPath          = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_DocsPath
        APIKey            = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_APIKey
        GITHUB_REPOSITORY = $env:GITHUB_REPOSITORY
    } | Format-List

}

$params = @{
    Name       = $name
    ModulePath = $modulePath
    APIKey     = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_APIKey
}
Publish-PSModule @params
