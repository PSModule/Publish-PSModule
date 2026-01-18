[CmdletBinding()]
param()

LogGroup 'Install dependencies' {
    $retryCount = 5
    $retryDelay = 10
    for ($i = 0; $i -lt $retryCount; $i++) {
        try {
            Install-PSResource -Name 'PSSemVer' -TrustRepository -Repository PSGallery
            break
        } catch {
            Write-Warning "Installation of PSSemVer failed with error: $_"
            if ($i -eq $retryCount - 1) {
                throw
            }
            Write-Warning "Retrying in $retryDelay seconds..."
            Start-Sleep -Seconds $retryDelay
        }
    }
}

LogGroup 'Load inputs' {
    $env:GITHUB_REPOSITORY_NAME = $env:GITHUB_REPOSITORY -replace '.+/'

    $name = if ([string]::IsNullOrEmpty($env:PSMODULE_PUBLISH_PSMODULE_INPUT_Name)) {
        $env:GITHUB_REPOSITORY_NAME
    } else {
        $env:PSMODULE_PUBLISH_PSMODULE_INPUT_Name
    }
    Write-Output "Module name: [$name]"
}

LogGroup 'Set configuration' {
    $autoCleanup = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_AutoCleanup -eq 'true'
    $autoPatching = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_AutoPatching -eq 'true'
    $incrementalPrerelease = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_IncrementalPrerelease -eq 'true'
    $datePrereleaseFormat = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_DatePrereleaseFormat
    $versionPrefix = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_VersionPrefix
    $whatIf = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_WhatIf -eq 'true'
    $ignoreLabels = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_IgnoreLabels -split ',' | ForEach-Object { $_.Trim() }
    $releaseType = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_ReleaseType  # 'Release', 'Prerelease', or 'None'
    $majorLabels = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_MajorLabels -split ',' | ForEach-Object { $_.Trim() }
    $minorLabels = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_MinorLabels -split ',' | ForEach-Object { $_.Trim() }
    $patchLabels = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_PatchLabels -split ',' | ForEach-Object { $_.Trim() }

    if ($whatIf) {
        $message = 'WhatIf mode is enabled. No actual releases will be created, ' +
        'no modules will be published, and no tags will be deleted.'
        Write-Host "::warning::$message"
    }

    [pscustomobject]@{
        AutoCleanup           = $autoCleanup
        AutoPatching          = $autoPatching
        IncrementalPrerelease = $incrementalPrerelease
        DatePrereleaseFormat  = $datePrereleaseFormat
        VersionPrefix         = $versionPrefix
        WhatIf                = $whatIf
        IgnoreLabels          = $ignoreLabels
        ReleaseType           = $releaseType
        MajorLabels           = $majorLabels
        MinorLabels           = $minorLabels
        PatchLabels           = $patchLabels
    } | Format-List | Out-String
}

LogGroup 'Event information - JSON' {
    $githubEventJson = Get-Content $env:GITHUB_EVENT_PATH
    $githubEventJson | Format-List | Out-String
}

LogGroup 'Event information - Object' {
    $githubEvent = $githubEventJson | ConvertFrom-Json
    $pull_request = $githubEvent.pull_request
    $githubEvent | Format-List | Out-String
}

LogGroup 'Event information - Details' {
    if (-not $pull_request) {
        throw 'GitHub event does not contain pull_request data. This script must be run from a pull_request event.'
    }
    $prHeadRef = $pull_request.head.ref

    Write-Output '-------------------------------------------------'
    Write-Output "PR Head Ref:                    [$prHeadRef]"
    Write-Output "ReleaseType:                    [$releaseType]"
    Write-Output '-------------------------------------------------'
}

LogGroup 'Pull request - details' {
    $pull_request | Format-List | Out-String
}

LogGroup 'Pull request - Labels' {
    $labels = @()
    $labels += $pull_request.labels.name
    $labels | Format-List | Out-String
}

LogGroup 'Calculate release type' {
    $prereleaseName = $prHeadRef -replace '[^a-zA-Z0-9]'

    # Validate ReleaseType - defensive check for invalid values.
    # Note: The empty check below should never trigger since action.yml provides a default of 'Release',
    # but is included for defensive programming in case the script is called directly or defaults change.
    $validReleaseTypes = @('Release', 'Prerelease', 'None')
    if ([string]::IsNullOrWhiteSpace($releaseType)) {
        Write-Error "ReleaseType input is required. Valid values are: $($validReleaseTypes -join ', ')"
        exit 1
    }
    if ($releaseType -notin $validReleaseTypes) {
        Write-Error "Invalid ReleaseType: [$releaseType]. Valid values are: $($validReleaseTypes -join ', ')"
        exit 1
    }

    $createRelease = $releaseType -eq 'Release'
    $createPrerelease = $releaseType -eq 'Prerelease'
    $shouldPublish = $createRelease -or $createPrerelease

    $ignoreRelease = ($labels | Where-Object { $ignoreLabels -contains $_ }).Count -gt 0
    if ($ignoreRelease) {
        Write-Output 'Ignoring release creation due to ignore label.'
        $shouldPublish = $false
    }

    # Only calculate version bumps if we intend to publish (ReleaseType is not 'None')
    $majorRelease = $false
    $minorRelease = $false
    $patchRelease = $false
    $hasVersionBump = $false

    if ($shouldPublish) {
        $majorRelease = ($labels | Where-Object { $majorLabels -contains $_ }).Count -gt 0
        $minorRelease = ($labels | Where-Object { $minorLabels -contains $_ }).Count -gt 0 -and -not $majorRelease
        $patchRelease = (
            ($labels | Where-Object { $patchLabels -contains $_ }
        ).Count -gt 0 -or $autoPatching) -and -not $majorRelease -and -not $minorRelease

        # Check if any version bump applies
        $hasVersionBump = $majorRelease -or $minorRelease -or $patchRelease
        if (-not $hasVersionBump) {
            Write-Output 'No version bump label found and AutoPatching is disabled. Skipping publish.'
            $shouldPublish = $false
        }
    } else {
        if ($ignoreRelease) {
            Write-Output 'Skipping version bump calculation due to ignore label.'
        } else {
            Write-Output "ReleaseType is [$releaseType]. Skipping version bump calculation."
        }
    }

    Write-Output '-------------------------------------------------'
    Write-Output "ReleaseType:                    [$releaseType]"
    Write-Output "AutoCleanup:                    [$autoCleanup]"
    Write-Output "Should publish:                 [$shouldPublish]"
    Write-Output "Create a release:               [$createRelease]"
    Write-Output "Create a prerelease:            [$createPrerelease]"
    Write-Output "Create a major release:         [$majorRelease]"
    Write-Output "Create a minor release:         [$minorRelease]"
    Write-Output "Create a patch release:         [$patchRelease]"
    Write-Output '-------------------------------------------------'
}
#endregion Calculate release type

# Initialize version-related variables with defaults
$newVersion = $null
$releases = @()
$prereleaseTagsToCleanup = ''

# Fetch releases if publishing OR if cleanup is enabled (cleanup can work independently)
if ($shouldPublish -or $autoCleanup) {
    #region Get releases
    LogGroup 'Get all releases - GitHub' {
        $releases = gh release list --json 'createdAt,isDraft,isLatest,isPrerelease,name,publishedAt,tagName' | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            Write-Error 'Failed to list all releases for the repo.'
            exit $LASTEXITCODE
        }
        $releases | Select-Object -Property name, isPrerelease, isLatest, publishedAt | Format-Table | Out-String
    }
    #endregion Get releases
}

# Version calculation is only needed when publishing
if ($shouldPublish) {
    #region Get versions
    LogGroup 'Get latest version - GitHub' {
        $latestRelease = $releases | Where-Object { $_.isLatest -eq $true }
        $latestRelease | Format-List | Out-String
        $ghReleaseVersionString = $latestRelease.tagName
        if (-not [string]::IsNullOrEmpty($ghReleaseVersionString)) {
            $ghReleaseVersion = New-PSSemVer -Version $ghReleaseVersionString
        } else {
            Write-Warning 'Could not find the latest release version. Using ''0.0.0'' as the version.'
            $ghReleaseVersion = New-PSSemVer -Version '0.0.0'
        }
        Write-Output '-------------------------------------------------'
        Write-Output 'GitHub version:'
        Write-Output $ghReleaseVersion.ToString()
        Write-Output '-------------------------------------------------'
    }

    LogGroup 'Get latest version - PSGallery' {
        $count = 5
        $delay = 10
        for ($i = 1; $i -le $count; $i++) {
            try {
                Write-Output "Finding module [$name] in the PowerShell Gallery."
                $latest = Find-PSResource -Name $name -Repository PSGallery -Verbose:$false
                Write-Output "$($latest | Format-Table | Out-String)"
                break
            } catch {
                if ($i -eq $count) {
                    Write-Warning "Failed to find the module [$name] in the PowerShell Gallery."
                    Write-Warning $_.Exception.Message
                }
                Start-Sleep -Seconds $delay
            }
        }
        if ($latest.Version) {
            $psGalleryVersion = New-PSSemVer -Version ($latest.Version).ToString()
        } else {
            Write-Warning 'Could not find module online. Using ''0.0.0'' as the version.'
            $psGalleryVersion = New-PSSemVer -Version '0.0.0'
        }
        Write-Output '-------------------------------------------------'
        Write-Output 'PSGallery version:'
        Write-Output $psGalleryVersion.ToString()
        Write-Output '-------------------------------------------------'
    }

    LogGroup 'Get latest version' {
        Write-Output "GitHub:    [$($ghReleaseVersion.ToString())]"
        Write-Output "PSGallery: [$($psGalleryVersion.ToString())]"
        $latestVersion = New-PSSemVer -Version ($psGalleryVersion, $ghReleaseVersion | Sort-Object -Descending | Select-Object -First 1)
        Write-Output '-------------------------------------------------'
        Write-Output 'Latest version:'
        Write-Output ($latestVersion | Format-Table | Out-String)
        Write-Output $latestVersion.ToString()
        Write-Output '-------------------------------------------------'
    }

    LogGroup 'Calculate new version' {
        # - Increment based on label on PR
        $newVersion = New-PSSemVer -Version $latestVersion
        $newVersion.Prefix = $versionPrefix
        if ($majorRelease) {
            Write-Output 'Incrementing major version.'
            $newVersion.BumpMajor()
        } elseif ($minorRelease) {
            Write-Output 'Incrementing minor version.'
            $newVersion.BumpMinor()
        } elseif ($patchRelease) {
            Write-Output 'Incrementing patch version.'
            $newVersion.BumpPatch()
        } else {
            Write-Output 'No version bump required.'
        }

        Write-Output "Partial new version: [$newVersion]"

        if ($createPrerelease -and $hasVersionBump) {
            Write-Output "Adding a prerelease tag to the version using the branch name [$prereleaseName]."
            Write-Output ($releases | Where-Object { $_.tagName -like "*$prereleaseName*" } |
                    Select-Object -Property name, isPrerelease, isLatest, publishedAt | Format-Table -AutoSize | Out-String)

            $newVersion.Prerelease = $prereleaseName
            Write-Output "Partial new version: [$newVersion]"

            if (-not [string]::IsNullOrEmpty($datePrereleaseFormat)) {
                Write-Output "Using date-based prerelease: [$datePrereleaseFormat]."
                $newVersion.Prerelease += "$(Get-Date -Format $datePrereleaseFormat)"
                Write-Output "Partial new version: [$newVersion]"
            }

            if ($incrementalPrerelease) {
                # Find the latest prerelease version
                $newVersionString = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)"

                # PowerShell Gallery
                $params = @{
                    Name        = $name
                    Version     = '*'
                    Prerelease  = $true
                    Repository  = 'PSGallery'
                    Verbose     = $false
                    ErrorAction = 'SilentlyContinue'
                }
                Write-Output 'Finding the latest prerelease version in the PowerShell Gallery.'
                Write-Output ($params | Format-Table | Out-String)
                $psGalleryPrereleases = Find-PSResource @params
                $psGalleryPrereleases = $psGalleryPrereleases | Where-Object { $_.Version -like "$newVersionString" }
                $psGalleryPrereleases = $psGalleryPrereleases | Where-Object { $_.Prerelease -like "$prereleaseName*" }
                $latestPSGalleryPrerelease = $psGalleryPrereleases.Prerelease | ForEach-Object {
                    [int]($_ -replace $prereleaseName)
                } | Sort-Object | Select-Object -Last 1
                Write-Output "PSGallery prerelease: [$latestPSGalleryPrerelease]"

                # GitHub
                $ghPrereleases = $releases | Where-Object { $_.tagName -like "*$newVersionString*" }
                $ghPrereleases = $ghPrereleases | Where-Object { $_.tagName -like "*$prereleaseName*" }
                $latestGHPrereleases = $ghPrereleases.tagName | ForEach-Object {
                    $number = $_
                    $number = $number -replace '\.'
                    $number = ($number -split $prereleaseName, 2)[-1]
                    [int]$number
                } | Sort-Object | Select-Object -Last 1
                Write-Output "GitHub prerelease: [$latestGHPrereleases]"

                # Handle null values explicitly to ensure Math.Max works correctly
                if ($null -eq $latestPSGalleryPrerelease) { $latestPSGalleryPrerelease = 0 }
                if ($null -eq $latestGHPrereleases) { $latestGHPrereleases = 0 }

                $latestPrereleaseNumber = [Math]::Max($latestPSGalleryPrerelease, $latestGHPrereleases)
                $latestPrereleaseNumber++
                $latestPrereleaseNumber = ([string]$latestPrereleaseNumber).PadLeft(3, '0')
                $newVersion.Prerelease += $latestPrereleaseNumber
            }
        }
        Write-Output '-------------------------------------------------'
        Write-Output 'New version:'
        Write-Output ($newVersion | Format-Table | Out-String)
        Write-Output $newVersion.ToString()
        Write-Output '-------------------------------------------------'
    }
    #endregion Calculate new version
}

#region Find prereleases to cleanup
# This runs independently when cleanup is enabled, even if not publishing
if ($autoCleanup) {
    LogGroup 'Find prereleases to cleanup' {
        $prereleasesToCleanup = $releases | Where-Object { $_.tagName -like "*$prereleaseName*" }
        $prereleasesToCleanup | Select-Object -Property name, publishedAt, isPrerelease, isLatest | Format-Table | Out-String
        $prereleaseTagsToCleanup = ($prereleasesToCleanup | ForEach-Object { $_.tagName }) -join ','
        Write-Output "Prereleases to cleanup: [$prereleaseTagsToCleanup]"
    }
}
#endregion Find prereleases to cleanup

LogGroup 'Store context in environment variables' {
    # Store values for subsequent steps by appending to GITHUB_ENV
    $newVersionString = if ($newVersion) { $newVersion.ToString() } else { '' }

    Add-Content -Path $env:GITHUB_ENV -Value "PUBLISH_CONTEXT_ShouldPublish=$($shouldPublish.ToString().ToLower())"
    Add-Content -Path $env:GITHUB_ENV -Value "PUBLISH_CONTEXT_ShouldCleanup=$($autoCleanup.ToString().ToLower())"
    Add-Content -Path $env:GITHUB_ENV -Value "PUBLISH_CONTEXT_CreateRelease=$($createRelease.ToString().ToLower())"
    Add-Content -Path $env:GITHUB_ENV -Value "PUBLISH_CONTEXT_CreatePrerelease=$($createPrerelease.ToString().ToLower())"
    Add-Content -Path $env:GITHUB_ENV -Value "PUBLISH_CONTEXT_MajorRelease=$($majorRelease.ToString().ToLower())"
    Add-Content -Path $env:GITHUB_ENV -Value "PUBLISH_CONTEXT_MinorRelease=$($minorRelease.ToString().ToLower())"
    Add-Content -Path $env:GITHUB_ENV -Value "PUBLISH_CONTEXT_PatchRelease=$($patchRelease.ToString().ToLower())"
    Add-Content -Path $env:GITHUB_ENV -Value "PUBLISH_CONTEXT_NewVersion=$newVersionString"
    Add-Content -Path $env:GITHUB_ENV -Value "PUBLISH_CONTEXT_PrereleaseName=$prereleaseName"
    Add-Content -Path $env:GITHUB_ENV -Value "PUBLISH_CONTEXT_PrereleaseTagsToCleanup=$prereleaseTagsToCleanup"
    Add-Content -Path $env:GITHUB_ENV -Value "PUBLISH_CONTEXT_PRNumber=$($pull_request.number.ToString())"
    Add-Content -Path $env:GITHUB_ENV -Value "PUBLISH_CONTEXT_PRHeadRef=$prHeadRef"

    Write-Output '-------------------------------------------------'
    Write-Output 'Stored environment variables:'
    [PSCustomObject]@{
        ShouldPublish           = $shouldPublish
        ShouldCleanup           = $autoCleanup
        CreateRelease           = $createRelease
        CreatePrerelease        = $createPrerelease
        MajorRelease            = $majorRelease
        MinorRelease            = $minorRelease
        PatchRelease            = $patchRelease
        NewVersion              = $newVersionString
        PrereleaseName          = $prereleaseName
        PrereleaseTagsToCleanup = $prereleaseTagsToCleanup
        PRNumber                = $pull_request.number
        PRHeadRef               = $prHeadRef
    } | Format-List | Out-String
    Write-Output '-------------------------------------------------'
}

Write-Output "Context initialization complete. ShouldPublish=[$shouldPublish], ShouldCleanup=[$autoCleanup]"
