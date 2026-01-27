[CmdletBinding()]
param()

$PSStyle.OutputRendering = 'Ansi'

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
        Write-Host "No prereleases found to cleanup for [$prereleaseName]."
        return
    }

    $tagsToDelete = $prereleaseTagsToCleanup -split ',' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if ($tagsToDelete.Count -eq 0) {
        Write-Host "No prereleases found to cleanup for [$prereleaseName]."
        return
    }

    Write-Host "Found $($tagsToDelete.Count) prereleases to cleanup:"
    $tagsToDelete | ForEach-Object { Write-Host "  - $_" }
    Write-Host ''

    foreach ($tag in $tagsToDelete) {
        Write-Host "Deleting prerelease: [$tag]"
        if ($whatIf) {
            Write-Host "WhatIf: gh release delete $tag --cleanup-tag --yes"
        } else {
            gh release delete $tag --cleanup-tag --yes
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to delete release [$tag]."
                exit $LASTEXITCODE
            }
            Write-Host "Successfully deleted release [$tag]."
        }
    }

    Write-Host "::notice::Cleaned up $($tagsToDelete.Count) prerelease(s) for [$prereleaseName]."
}
