#REQUIRES -Modules Utilities, PowerShellGet, Microsoft.PowerShell.PSResourceGet

function Publish-PSModule {
    <#
        .SYNOPSIS
        Publishes a module to the PowerShell Gallery and GitHub Pages.

        .DESCRIPTION
        Publishes a module to the PowerShell Gallery and GitHub Pages.

        .EXAMPLE
        Publish-PSModule -Name 'PSModule.FX' -APIKey $env:PSGALLERY_API_KEY
    #>
    [CmdletBinding()]
    param(
        # Name of the module to process.
        [Parameter()]
        [string] $Name,

        # The path to the module to process.
        [Parameter(Mandatory)]
        [string] $ModulePath,

        # The path to the documentation to process.
        [Parameter(Mandatory)]
        [string] $DocsPath,

        # The API key for the destination repository.
        [Parameter(Mandatory)]
        [string] $APIKey
    )
    #region Initializing
    Start-LogGroup 'Initializing...'
    Add-PSModulePath -Path (Split-Path -Path $ModulePath -Parent)
    $manifestFilePath = Join-Path $ModulePath "$Name.psd1"
    Write-Verbose "Module manifest file path: [$manifestFilePath]"
    #endregion Initializing

    #region Generate-Version
    Start-LogGroup 'Generate-Version'

    [Version]$newVersion = '0.0.0'
    try {
        $onlineVersion = [Version](Find-Module $Name -Verbose:$false).Version
    } catch {
        $onlineVersion = $newVersion
        Write-Warning "Could not find module online. Using [$($onlineVersion.ToString())]"
    }
    Write-Warning "Online: [$($onlineVersion.ToString())]"
    $manifestVersion = [Version](Test-ModuleManifest $manifestFilePath -Verbose:$false).Version
    Write-Warning "Manifest: [$($manifestVersion.ToString())]"

    Write-Verbose "branch is: [$env:GITHUB_REF_NAME]"

    if ($manifestVersion.Major -gt $onlineVersion.Major) {
        $newVersionMajor = $manifestVersion.Major
        $newVersionMinor = 0
        $newVersionBuild = 0
    } else {
        $newVersionMajor = $onlineVersion.Major
        if ($manifestVersion.Minor -gt $onlineVersion.Minor) {
            $newVersionMinor = $manifestVersion.Minor
            $newVersionBuild = 0
        } else {
            $newVersionMinor = $onlineVersion.Minor
            $newVersionBuild = $onlineVersion.Build + 1
        }
    }
    [Version]$newVersion = [version]::new($newVersionMajor, $newVersionMinor, $newVersionBuild)
    Write-Warning "newVersion: [$($newVersion.ToString())]"

    if ($env:GITHUB_REF_NAME -ne 'main') {
        Write-Verbose "Not on main, but on [$env:GITHUB_REF_NAME]"
        Write-Verbose 'Generate pre-release version'
        $prerelease = $env:GITHUB_REF_NAME -replace '[^a-zA-Z0-9]', ''
        Write-Verbose "Prerelease is: [$prerelease]"
        if ($newVersion -ge [version]'1.0.0') {
            Write-Verbose "Version is greater than 1.0.0 -> Update-PSModuleManifest with prerelease [$prerelease]"
            Update-ModuleManifest -Path $manifestFilePath -Prerelease $prerelease -ErrorAction Continue
        }
    }

    Write-Verbose 'Bump module version -> module metadata: Update-ModuleMetadata'
    Update-ModuleManifest -Path $manifestFilePath -ModuleVersion $newVersion -ErrorAction Continue

    #TODO: Slim-PSModuleManifest -Path $manifestFilePath

    Stop-LogGroup
    #endregion Generate-Version

    #region New-GitHubRelease
    Start-LogGroup 'New-GitHubRelease'
    Write-Verbose 'Create new GitHub release'
    gh release create $newVersion --title $newVersion --generate-notes --target $env:GITHUB_REF_NAME
    # gh release edit $newVersion -tag "$newVersion-$prerelease" --prerelease
    Write-Verbose "Publish GitHub release for [$newVersion]"
    gh release edit $newVersion --draft=false
    Stop-LogGroup
    #endregion New-GitHubRelease

    #region Publish-Docs
    Start-LogGroup "Publish docs - [$DocsPath]"
    Write-Verbose 'Publish docs to GitHub Pages'
    Write-Verbose 'Update docs path: Update-ModuleMetadata'

    Stop-LogGroup
    #endregion Publish-Docs

    #region Publish-ToPSGallery
    Start-LogGroup "Publish-ToPSGallery"
    Write-Verbose "Publish module to PowerShell Gallery using [$APIKey]"
    Publish-PSResource -Path $ModulePath -Repository PSGallery -ApiKey $APIKey -Verbose
    Stop-LogGroup
    #endregion Publish-ToPSGallery
}
