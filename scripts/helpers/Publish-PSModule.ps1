#TODO: Requires -Modules platyPS, PowerShellGet, PackageManagement

function Publish-PSModule {
    <#
        .SYNOPSIS
        Publishes a module to the PowerShell Gallery and GitHub Pages.

        .DESCRIPTION
        Publishes a module to the PowerShell Gallery and GitHub Pages.

        .EXAMPLE
        Publish-PSModule -Name 'PSModule.FX' -APIKey $env:PSGALLERY_API_KEY
    #>
    [Alias('Release-Module')]
    [CmdletBinding(SupportsShouldProcess)]
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
    $task = New-Object System.Collections.Generic.List[string]
    #region Publish-Module
    $task.Add('Release-Module')
    Start-LogGroup "[$($task -join '] - [')] - Starting..."

    ########################
    # Gather some basic info
    ########################

    Add-PSModulePath -Path (Split-Path -Path $ModulePath -Parent)

    $manifestFilePath = "$ModulePath\$Name.psd1"
    $task.Add($Name)
    Start-LogGroup "[$($task -join '] - [')] - Starting..."

    #region Generate-Version
    $task.Add('Generate-Version')
    Start-LogGroup "[$($task -join '] - [')]"
    Write-Verbose "[$($task -join '] - [')] - Generate version"

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

    Write-Verbose "[$($task -join '] - [')] - Create draft release with version"
    gh release create $newVersion --title $newVersion --generate-notes --draft --target $env:GITHUB_REF_NAME

    if ($env:GITHUB_REF_NAME -ne 'main') {
        Write-Verbose "[$($task -join '] - [')] - Not on main, but on [$env:GITHUB_REF_NAME]"
        Write-Verbose "[$($task -join '] - [')] - Generate pre-release version"
        $prerelease = $env:GITHUB_REF_NAME -replace '[^a-zA-Z0-9]', ''
        Write-Verbose "[$($task -join '] - [')] - Prerelease is: [$prerelease]"
        if ($newVersion -ge [version]'1.0.0') {
            Write-Verbose "[$($task -join '] - [')] - Version is greater than 1.0.0 -> Update-PSModuleManifest with prerelease [$prerelease]"
            Update-PSModuleManifest -Path $manifestFilePath -Prerelease $prerelease -ErrorAction Continue
            gh release edit $newVersion -tag "$newVersion-$prerelease" --prerelease
        }
    }

    Write-Verbose "[$($task -join '] - [')] - Bump module version -> module metadata: Update-ModuleMetadata"
    Update-PSModuleManifest -Path $manifestFilePath -ModuleVersion $newVersion -ErrorAction Continue

    Start-LogGroup "[$($task -join '] - [')] - Done"
    $task.RemoveAt($task.Count - 1)
    #endregion Generate-Version

    #region Publish-Docs
    $task.Add('Publish-Docs')
    Start-LogGroup "[$($task -join '] - [')]"
    Start-LogGroup "[$($task -join '] - [')] - Docs - [$DocsPath]"
    Write-Verbose "[$($task -join '] - [')] - Publish docs to GitHub Pages"
    Write-Verbose "[$($task -join '] - [')] - Update docs path: Update-ModuleMetadata"

    # What about updateable help?
    # https://learn.microsoft.com/en-us/powershell/scripting/developer/help/supporting-updatable-help?view=powershell-7.3

    Start-LogGroup "[$($task -join '] - [')] - Done"
    $task.RemoveAt($task.Count - 1)
    #endregion Publish-Docs

    #region Publish-ToPSGallery
    $task.Add('Publish-ToPSGallery')
    Start-LogGroup "[$($task -join '] - [')]"
    Start-LogGroup "[$($task -join '] - [')] - Do something"

    Write-Verbose "[$($task -join '] - [')] - Publish module to PowerShell Gallery using [$APIKey]"
    Publish-PSResource -Path $ModulePath -Repository PSGallery -ApiKey $APIKey -Verbose

    Write-Verbose "[$($task -join '] - [')] - Publish GitHub release for [$newVersion]"
    gh release edit $newVersion --draft=false

    Write-Verbose "[$($task -join '] - [')] - Doing something"
    Start-LogGroup "[$($task -join '] - [')] - Done"
    $task.RemoveAt($task.Count - 1)
    #endregion Publish-ToPSGallery

    $task.RemoveAt($task.Count - 1)
    Start-LogGroup "[$($task -join '] - [')] - Stopping..."
    Stop-LogGroup
    #endregion Publish-Module
}
