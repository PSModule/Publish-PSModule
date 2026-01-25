[CmdletBinding()]
param()

Import-Module -Name 'Helpers' -Force

$prereleaseName = $env:PUBLISH_CONTEXT_PrereleaseName
$prereleaseTagsToCleanup = $env:PUBLISH_CONTEXT_PrereleaseTagsToCleanup
$whatIf = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_WhatIf -eq 'true'

if ([string]::IsNullOrWhiteSpace($prereleaseName)) {
    Write-Error 'PUBLISH_CONTEXT_PrereleaseName is not set. Run init.ps1 first.'
    exit 1
}

LogGroup "Cleanup prereleases for [$prereleaseName]" {
    if ([string]::IsNullOrWhiteSpace($prereleaseTagsToCleanup)) {
        Write-Output "No prereleases found to cleanup for [$prereleaseName]."
        return
    }

    $tagsToDelete = $prereleaseTagsToCleanup -split ',' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if ($tagsToDelete.Count -eq 0) {
        Write-Output "No prereleases found to cleanup for [$prereleaseName]."
        return
    }

    Write-Output "Found $($tagsToDelete.Count) prereleases to cleanup:"
    $tagsToDelete | ForEach-Object { Write-Output "  - $_" }
    Write-Output ''

    foreach ($tag in $tagsToDelete) {
        Write-Output "Deleting prerelease: [$tag]"
        if ($whatIf) {
            Write-Output "WhatIf: gh release delete $tag --cleanup-tag --yes"
        } else {
            gh release delete $tag --cleanup-tag --yes
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to delete release [$tag]."
                exit $LASTEXITCODE
            }
            Write-Output "Successfully deleted release [$tag]."
        }
    }

    Write-Host "::notice::Cleaned up $($tagsToDelete.Count) prerelease(s) for [$prereleaseName]."
}
