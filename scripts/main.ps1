[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $APIKey
)
$task = New-Object System.Collections.Generic.List[string]
#region Publish-Module
$task.Add('Release-Module')
Write-Output "::group::[$($task -join '] - [')] - Starting..."

Import-Module PackageManagement, PowerShellGet -Verbose:$false -ErrorAction Stop

########################
# Gather some basic info
########################

$outputPath = Get-Item -Path .\outputs\ | Select-Object -ExpandProperty FullName
$env:PSModulePath += ":$SRCPath"
$env:PSModulePath -Split ':'

$moduleFolders = Get-ChildItem -Path $outputPath -Directory -Exclude 'docs'

foreach ($module in $moduleFolders) {
    $moduleName = $module.Name
    $manifestFilePath = "$module\$moduleName.psd1"
    $task.Add($moduleName)
    Write-Output "::group::[$($task -join '] - [')] - Starting..."

    #region Generate-Version
    $task.Add('Generate-Version')
    Write-Output "::group::[$($task -join '] - [')]"
    Write-Verbose "[$($task -join '] - [')] - [] - Generate version"
    Write-Verbose "[$($task -join '] - [')] - [] - Generate pre-release version if not on main"
    Write-Verbose "[$($task -join '] - [')] - [] - Create new release with version (prerelease)"


    [Version]$newVersion = '0.0.0'

    try {
        $onlineVersion = [Version](Find-Module $moduleName -Verbose:$false).Version
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
        Write-Verbose "prerelease is: [$env:GITHUB_REF_NAME]"
        Update-ModuleManifest -Path $manifestFilePath -Prerelease $env:GITHUB_REF_NAME -ErrorAction Continue -Verbose:$false -WhatIf:$WhatIf
    }

    Write-Verbose "[$($task -join '] - [')] - [] - Bump module version -> module metadata: Update-ModuleMetadata"
    Update-ModuleManifest -Path $manifestFilePath -ModuleVersion $newVersion -ErrorAction Continue -Verbose:$false -WhatIf:$WhatIf

    Write-Output "::group::[$($task -join '] - [')] - Done"
    $task.RemoveAt($task.Count - 1)
    #endregion Generate-Version

    #region Publish-Docs
    $task.Add('Publish-Docs')
    Write-Output "::group::[$($task -join '] - [')]"
    Write-Output "::group::[$($task -join '] - [')] - Do something"

    Write-Verbose "[$($task -join '] - [')] - [] - Publish docs to GitHub Pages"
    Write-Verbose "[$($task -join '] - [')] - [] - Update docs path: Update-ModuleMetadata"
    # What about updateable help? https://learn.microsoft.com/en-us/powershell/scripting/developer/help/supporting-updatable-help?view=powershell-7.3

    Write-Output "::group::[$($task -join '] - [')] - Done"
    $task.RemoveAt($task.Count - 1)
    #endregion Publish-Docs

    #region Publish-ToPSGallery
    $task.Add('Publish-ToPSGallery')
    Write-Output "::group::[$($task -join '] - [')]"
    Write-Output "::group::[$($task -join '] - [')] - Do something"

    Write-Verbose "[$($task -join '] - [')] - [] - Publish module to PowerShell Gallery using [$APIKey]"
    Publish-Module -Path "$module" -NuGetApiKey $APIKey -WhatIf:$WhatIf

    Write-Verbose "[$($task -join '] - [')] - [] - Doing something"
    Write-Output "::group::[$($task -join '] - [')] - Done"
    $task.RemoveAt($task.Count - 1)
    #endregion Publish-ToPSGallery

}

$task.RemoveAt($task.Count - 1)
Write-Output "::group::[$($task -join '] - [')] - Stopping..."
Write-Output '::endgroup::'
#endregion Publish-Module
