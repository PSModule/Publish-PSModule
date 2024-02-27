[Cmdletbinding()]
param()

$scriptName = $MyInvocation.MyCommand.Name
Write-Verbose "[$scriptName] Importing subcomponents"

#region - Data import
Write-Verbose "[$scriptName] - [data] - Processing folder"
$dataFolder = (Join-Path $PSScriptRoot 'data')
Write-Verbose "[$scriptName] - [data] - [$dataFolder]"
Get-ChildItem -Path "$dataFolder" -Recurse -Force -Include '*.psd1' -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Verbose "[$scriptName] - [data] - [$($_.Name)] - Importing"
    New-Variable -Name $_.BaseName -Value (Import-PowerShellDataFile -Path $_.FullName) -Force
    Write-Verbose "[$scriptName] - [data] - [$($_.Name)] - Done"
}

Write-Verbose "[$scriptName] - [data] - Done"
#endregion - Data import

#region - From /public
Write-Verbose "[$scriptName] - [/public] - Processing folder"

#region - From /public/Test-PSModuleTest.ps1
Write-Verbose "[$scriptName] - [/public/Test-PSModuleTest.ps1] - Importing"

Function Test-PSModuleTest {
    <#
        .SYNOPSIS
        Performs tests on a module.

        .EXAMPLE
        Test-PSModuleTest -Name 'World'

        "Hello, World!"
    #>
    [CmdletBinding()]
    param (
        # Name of the person to greet.
        [Parameter(Mandatory)]
        [string] $Name
    )
    Write-Output "Hello, $Name!"
}

Write-Verbose "[$scriptName] - [/public/Test-PSModuleTest.ps1] - Done"
#endregion - From /public/Test-PSModuleTest.ps1

Write-Verbose "[$scriptName] - [/public] - Done"
#endregion - From /public

Export-ModuleMember -Function 'Test-PSModuleTest' -Cmdlet '' -Variable '' -Alias '*'
