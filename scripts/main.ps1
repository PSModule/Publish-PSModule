[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string] $Message
)
$Task = ($MyInvocation.MyCommand.Name).split('.')[0]

Write-Verbose "$Task`: Starting..."

Write-Verbose "$Task`: Message: $Message"
Write-Verbose "$Task`: Bump repo version"
Write-Verbose "$Task`: Bump module version -> meta"
Write-Verbose "$Task`: Publish docs to GitHub Pages"
Write-Verbose "$Task`: Publish module to PowerShell Gallery"

Write-Verbose "$Task`: Stopping..."
