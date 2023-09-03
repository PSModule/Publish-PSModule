[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $APIKey
)
$Task = 'Publish-Module'

Write-Verbose "$Task`: Starting..."

Write-Verbose "$Task`: Generate version"
Write-Verbose "$Task`: Generate pre-release version if not on main"
Write-Verbose "$Task`: Create new release with version (prerelease)"
Write-Verbose "$Task`: Bump module version -> module metadata: Update-ModuleMetadata"
Write-Verbose "$Task`: Publish docs to GitHub Pages"
Write-Verbose "$Task`: Update docs path: Update-ModuleMetadata"
# What about updateable help? https://learn.microsoft.com/en-us/powershell/scripting/developer/help/supporting-updatable-help?view=powershell-7.3
Write-Verbose "$Task`: Publish module to PowerShell Gallery using [$APIKey]"
Publish-Module -Path $Path -NuGetApiKey $APIKey -Verbose -WhatIf

Write-Verbose "$Task`: Stopping..."
