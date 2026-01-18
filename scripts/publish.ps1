[CmdletBinding()]
param()

#region Load inputs
$env:GITHUB_REPOSITORY_NAME = $env:GITHUB_REPOSITORY -replace '.+/'

$name = if ([string]::IsNullOrEmpty($env:PSMODULE_PUBLISH_PSMODULE_INPUT_Name)) {
    $env:GITHUB_REPOSITORY_NAME
} else {
    $env:PSMODULE_PUBLISH_PSMODULE_INPUT_Name
}
$modulePath = Resolve-Path -Path "$env:PSMODULE_PUBLISH_PSMODULE_INPUT_ModulePath/$name" | Select-Object -ExpandProperty Path
$apiKey = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_APIKey

Write-Output "Module name: [$name]"
Write-Output "Module path: [$modulePath]"
#endregion Load inputs

#region Load publish context from environment
Set-GitHubLogGroup 'Load publish context from environment' {
    $createRelease = $env:PUBLISH_CONTEXT_CreateRelease -eq 'true'
    $createPrerelease = $env:PUBLISH_CONTEXT_CreatePrerelease -eq 'true'
    $newVersionString = $env:PUBLISH_CONTEXT_NewVersion
    $prNumber = $env:PUBLISH_CONTEXT_PRNumber
    $prHeadRef = $env:PUBLISH_CONTEXT_PRHeadRef
    $whatIf = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_WhatIf -eq 'true'
    $usePRBodyAsReleaseNotes = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_UsePRBodyAsReleaseNotes -eq 'true'
    $usePRTitleAsReleaseName = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_UsePRTitleAsReleaseName -eq 'true'
    $usePRTitleAsNotesHeading = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_UsePRTitleAsNotesHeading -eq 'true'

    if ([string]::IsNullOrWhiteSpace($newVersionString)) {
        Write-Error 'PUBLISH_CONTEXT_NewVersion is not set. Run init.ps1 first.'
        exit 1
    }

    $newVersion = New-PSSemVer -Version $newVersionString

    Write-Output '-------------------------------------------------'
    Write-Output 'Publish context:'
    Write-Output "  CreateRelease:       [$createRelease]"
    Write-Output "  CreatePrerelease:    [$createPrerelease]"
    Write-Output "  NewVersion:          [$($newVersion.ToString())]"
    Write-Output "  PRNumber:            [$prNumber]"
    Write-Output "  PRHeadRef:           [$prHeadRef]"
    Write-Output "  WhatIf:              [$whatIf]"
    Write-Output '-------------------------------------------------'
}
#endregion Load publish context from environment

#region Load PR information
Set-GitHubLogGroup 'Load PR information' {
    $githubEventJson = Get-Content $env:GITHUB_EVENT_PATH
    $githubEvent = $githubEventJson | ConvertFrom-Json
    $pull_request = $githubEvent.pull_request
    if (-not $pull_request) {
        throw 'GitHub event does not contain pull_request data. This script must be run from a pull_request event.'
    }
}
#endregion Load PR information

#region Validate manifest and set module path
Set-GitHubLogGroup 'Validate manifest and set module path' {
    Add-PSModulePath -Path (Split-Path -Path $modulePath -Parent)
    $manifestFilePath = Join-Path $modulePath "$name.psd1"
    Write-Output "Module manifest file path: [$manifestFilePath]"
    if (-not (Test-Path -Path $manifestFilePath)) {
        Write-Error "Module manifest file not found at [$manifestFilePath]"
        exit 1
    }
}
#endregion Validate manifest and set module path

#region Update module manifest
Set-GitHubLogGroup 'Update module manifest' {
    Write-Output 'Bump module version -> module metadata: Update-ModuleMetadata'
    $manifestNewVersion = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)"
    Set-ModuleManifest -Path $manifestFilePath -ModuleVersion $manifestNewVersion -Verbose:$false
    if ($createPrerelease) {
        Write-Output "Prerelease is: [$($newVersion.Prerelease)]"
        Set-ModuleManifest -Path $manifestFilePath -Prerelease $($newVersion.Prerelease) -Verbose:$false
    }

    Show-FileContent -Path $manifestFilePath
}
#endregion Update module manifest

#region Install module dependencies
Set-GitHubLogGroup 'Install module dependencies' {
    Resolve-PSModuleDependency -ManifestFilePath $manifestFilePath
}
#endregion Install module dependencies

#region Publish to PSGallery
Set-GitHubLogGroup 'Publish-ToPSGallery' {
    if ($createPrerelease) {
        $publishPSVersion = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)-$($newVersion.Prerelease)"
    } else {
        $publishPSVersion = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)"
    }
    $psGalleryReleaseLink = "https://www.powershellgallery.com/packages/$name/$publishPSVersion"
    Write-Output "Publish module to PowerShell Gallery using [$apiKey]"
    if ($whatIf) {
        Write-Output "Publish-PSResource -Path $modulePath -Repository PSGallery -ApiKey $apiKey"
    } else {
        try {
            Publish-PSResource -Path $modulePath -Repository PSGallery -ApiKey $apiKey
        } catch {
            Write-Error $_.Exception.Message
            exit 1
        }
    }
    if ($whatIf) {
        Write-Output (
            "gh pr comment $prNumber -b " +
            "'Module [$name - $publishPSVersion]($psGalleryReleaseLink) published to the PowerShell Gallery.'"
        )
    } else {
        Write-Host "::notice::Module [$name - $publishPSVersion] published to the PowerShell Gallery."
        gh pr comment $prNumber -b "Module [$name - $publishPSVersion]($psGalleryReleaseLink) published to the PowerShell Gallery."
        if ($LASTEXITCODE -ne 0) {
            Write-Error 'Failed to comment on the pull request.'
            exit $LASTEXITCODE
        }
    }
}
#endregion Publish to PSGallery

#region Create GitHub Release
Set-GitHubLogGroup 'New-GitHubRelease' {
    Write-Output 'Create new GitHub release'
    $releaseCreateCommand = @('release', 'create', $newVersion.ToString())
    $notesFilePath = $null

    # Add title parameter
    if ($usePRTitleAsReleaseName -and $pull_request.title) {
        $prTitle = $pull_request.title
        $releaseCreateCommand += @('--title', $prTitle)
        Write-Output "Using PR title as release name: [$prTitle]"
    } else {
        $releaseCreateCommand += @('--title', $newVersion.ToString())
    }

    # Build release notes content. Uses temp file to avoid escaping issues with special characters.
    # Precedence rules for the three UsePR* parameters:
    #   1. UsePRTitleAsNotesHeading + UsePRBodyAsReleaseNotes: Creates "# Title (#PR)\n\nBody" format.
    #      Requires both parameters enabled AND both PR title and body to be present.
    #   2. UsePRBodyAsReleaseNotes only: Uses PR body as-is for release notes.
    #      Takes effect when heading option is disabled/missing title, but body is available.
    #   3. Fallback: Auto-generates notes via GitHub's --generate-notes when no PR content is used.
    if ($usePRTitleAsNotesHeading -and $usePRBodyAsReleaseNotes -and $pull_request.title -and $pull_request.body) {
        # Path 1: Full PR-based notes with title as H1 heading and PR number link
        $prTitle = $pull_request.title
        $prBody = $pull_request.body
        $notes = "# $prTitle (#$prNumber)`n`n$prBody"
        $notesFilePath = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $notesFilePath -Value $notes -Encoding utf8
        $releaseCreateCommand += @('--notes-file', $notesFilePath)
        Write-Output 'Using PR title as H1 heading with link and body as release notes'
    } elseif ($usePRBodyAsReleaseNotes -and $pull_request.body) {
        # Path 2: PR body only - no heading, just the body content
        $prBody = $pull_request.body
        $notesFilePath = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $notesFilePath -Value $prBody -Encoding utf8
        $releaseCreateCommand += @('--notes-file', $notesFilePath)
        Write-Output 'Using PR body as release notes'
    } else {
        # Path 3: Fallback to GitHub's auto-generated release notes
        $releaseCreateCommand += @('--generate-notes')
    }

    # Add remaining parameters
    if ($createPrerelease) {
        $releaseCreateCommand += @('--target', $prHeadRef, '--prerelease')
    }

    if ($whatIf) {
        Write-Output "WhatIf: gh $($releaseCreateCommand -join ' ')"
    } else {
        $releaseURL = gh @releaseCreateCommand
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create the release [$newVersion]."
            exit $LASTEXITCODE
        }
    }

    # Clean up temporary notes file if created
    if ($notesFilePath -and (Test-Path -Path $notesFilePath)) {
        Remove-Item -Path $notesFilePath -Force
    }

    if ($whatIf) {
        Write-Output (
            "gh pr comment $prNumber -b " +
            "'GitHub release for $name $newVersion has been created.'"
        )
    } else {
        gh pr comment $prNumber -b "GitHub release for $name [$newVersion]($releaseURL) has been created."
        if ($LASTEXITCODE -ne 0) {
            Write-Error 'Failed to comment on the pull request.'
            exit $LASTEXITCODE
        }
    }
    Write-Host "::notice::Release created: [$newVersion]"
}
#endregion Create GitHub Release

Write-Output "Publishing complete. Version: [$($newVersion.ToString())]"
