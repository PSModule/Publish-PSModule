[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $APIKey
)
$Task = ($MyInvocation.MyCommand.Name).split('.')[0]

Write-Verbose "$Task`: Starting..."

Write-Verbose "$Task`: Generate version"
Write-Verbose "$Task`: Bump repo version"
Write-Verbose "$Task`: Bump module version -> module metadata: Update-ModuleMetadata"
Write-Verbose "$Task`: Publish docs to GitHub Pages"
Write-Verbose "$Task`: Update docs path: Update-ModuleMetadata"
Write-Verbose "$Task`: Publish module to PowerShell Gallery using [$APIKey]"

Write-Verbose "$Task`: Stopping..."


function Publish-Module {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string] $ModuleName,

        [Parameter()]
        [string] $APIKey
    )

    $SRCPath = Get-Item -Path .\src\ | Select-Object -ExpandProperty FullName
    $env:PSModulePath += ":$SRCPath"
    $env:PSModulePath -Split ':'

    $Manifest = Invoke-Expression (Get-Content -Path "src/$ModuleName/$ModuleName.psd1" -Raw)
    foreach ($Module in $Manifest.RequiredModules) {
        $InstallParams = @{}

        if ($Module -is [string]) {
            $InstallParams.Name = $Module
        } else {
            $InstallParams.Name = $Module.ModuleName
            $InstallParams.MinimumVersion = $Module.ModuleVersion
            $InstallParams.RequiredVersion = $Module.RequiredVersion
        }
        $InstallParams.Verbose = $true
        $InstallParams.Force = $true

        Install-Module @InstallParams
    }

    .\scripts\Set-ModuleVersion.ps1 -ModuleName $ModuleName -Verbose
    Publish-Module -Path "src/$ModuleName" -NuGetApiKey $APIKey -Verbose

}
