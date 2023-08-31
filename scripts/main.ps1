[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $APIKey
)
$Task = ($MyInvocation.MyCommand.Name).split('.')[0]

Write-Verbose "$Task`: Starting..."

Write-Verbose "$Task`: Generate version"
Write-Verbose "$Task`: Generate pre-release version if not on main"
Write-Verbose "$Task`: Create new release with version (prerelease)"
Write-Verbose "$Task`: Bump module version -> module metadata: Update-ModuleMetadata"
Write-Verbose "$Task`: Publish docs to GitHub Pages"
Write-Verbose "$Task`: Update docs path: Update-ModuleMetadata"
Write-Verbose "$Task`: Publish module to PowerShell Gallery using [$APIKey]"
Publish-Module -Path "src/$ModuleName" -NuGetApiKey $APIKey -Verbose -WhatIf

Write-Verbose "$Task`: Stopping..."


