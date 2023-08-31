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
