[CmdletBinding()]
param()

$retryCount = 5
$retryDelay = 10
for ($i = 0; $i -lt $retryCount; $i++) {
    try {
        Install-PSResource -Name 'PSSemVer' -TrustRepository -Repository PSGallery
        break
    } catch {
        Write-Warning "Installation of $($psResourceParams.Name) failed with error: $_"
        if ($i -eq $retryCount - 1) {
            throw
        }
        Write-Warning "Retrying in $retryDelay seconds..."
        Start-Sleep -Seconds $retryDelay
    }
}

$path = (Join-Path -Path $PSScriptRoot -ChildPath 'helpers')
LogGroup "Loading helper scripts from [$path]" {
    Get-ChildItem -Path $path -Filter '*.ps1' -Recurse | ForEach-Object {
        Write-Verbose "[$($_.FullName)]"
        . $_.FullName
    }
}

LogGroup 'Loading inputs' {
    $name = if ([string]::IsNullOrEmpty($env:PSMODULE_PUBLISH_PSMODULE_INPUT_Name)) {
        $env:GITHUB_REPOSITORY_NAME
    } else {
        $env:PSMODULE_PUBLISH_PSMODULE_INPUT_Name
    }
    $modulePath = Resolve-Path -Path "$env:PSMODULE_PUBLISH_PSMODULE_INPUT_ModulePath/$name" | Select-Object -ExpandProperty Path
    [pscustomobject]@{
        Name       = $name
        ModulePath = $modulePath
        APIKey     = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_APIKey
    } | Format-List | Out-String

}

$params = @{
    Name       = $name
    ModulePath = $modulePath
    APIKey     = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_APIKey
}
Publish-PSModule @params
