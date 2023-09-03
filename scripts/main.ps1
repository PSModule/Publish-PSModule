[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $APIKey
)
$task = New-Object System.Collections.Generic.List[string]
#region Publish-Module
$task.Add('Publish-Module')
Write-Output "::group::[$($task -join '] - [')] - Starting..."



########################
# Gather some basic info
########################



#region Generate-Version
$task.Add('Generate-Version')
Write-Output "::group::[$($task -join '] - [')]"
Write-Output "::group::[$($task -join '] - [')] - Do something"

Write-Verbose "[$($task -join '] - [')] - [] - Generate version"
Write-Verbose "[$($task -join '] - [')] - [] - Generate pre-release version if not on main"
Write-Verbose "[$($task -join '] - [')] - [] - Create new release with version (prerelease)"
Write-Verbose "[$($task -join '] - [')] - [] - Bump module version -> module metadata: Update-ModuleMetadata"

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



#region Publsih-ToPSGallery
$task.Add('Publsih-ToPSGallery')
Write-Output "::group::[$($task -join '] - [')]"
Write-Output "::group::[$($task -join '] - [')] - Do something"

Write-Verbose "[$($task -join '] - [')] - [] - Publish module to PowerShell Gallery using [$APIKey]"
Publish-Module -Path $Path -NuGetApiKey $APIKey -Verbose -WhatIf

Write-Verbose "[$($task -join '] - [')] - [] - Doing something"
Write-Output "::group::[$($task -join '] - [')] - Done"
$task.RemoveAt($task.Count - 1)
#endregion Publsih-ToPSGallery



$task.RemoveAt($task.Count - 1)
Write-Output "::group::[$($task -join '] - [')] - Stopping..."
Write-Output '::endgroup::'
#endregion Publish-Module
