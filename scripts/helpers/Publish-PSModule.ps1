﻿function Publish-PSModule {
    <#
        .SYNOPSIS
        Publishes a module to the PowerShell Gallery and creates a GitHub Release.

        .DESCRIPTION
        Publishes a module to the PowerShell Gallery and creates a GitHub Release.

        .EXAMPLE
        Publish-PSModule -Name 'PSModule.FX' -APIKey $env:PSGALLERY_API_KEY
    #>
    [OutputType([void])]
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '', Scope = 'Function',
        Justification = 'LogGroup - Scoping affects the variables line of sight.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseDeclaredVarsMoreThanAssignments', '',
        Justification = 'LogGroup - Scoping affects the variables line of sight.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost', '',
        Justification = 'Log outputs to GitHub Actions logs.'
    )]
    param(
        # Name of the module to process.
        [Parameter()]
        [string] $Name,

        # The path to the module to process.
        [Parameter(Mandatory)]
        [string] $ModulePath,

        # The API key for the destination repository.
        [Parameter(Mandatory)]
        [string] $APIKey
    )

    Set-GitHubLogGroup 'Set configuration' {
        $autoCleanup = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_AutoCleanup -eq 'true'
        $autoPatching = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_AutoPatching -eq 'true'
        $incrementalPrerelease = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_IncrementalPrerelease -eq 'true'
        $datePrereleaseFormat = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_DatePrereleaseFormat
        $versionPrefix = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_VersionPrefix
        $whatIf = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_WhatIf -eq 'true'
        $ignoreLabels = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_IgnoreLabels -split ',' | ForEach-Object { $_.Trim() }
        $majorLabels = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_MajorLabels -split ',' | ForEach-Object { $_.Trim() }
        $minorLabels = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_MinorLabels -split ',' | ForEach-Object { $_.Trim() }
        $patchLabels = $env:PSMODULE_PUBLISH_PSMODULE_INPUT_PatchLabels -split ',' | ForEach-Object { $_.Trim() }

        [pscustomobject]@{
            AutoCleanup           = $autoCleanup
            AutoPatching          = $autoPatching
            IncrementalPrerelease = $incrementalPrerelease
            DatePrereleaseFormat  = $datePrereleaseFormat
            VersionPrefix         = $versionPrefix
            WhatIf                = $whatIf
            IgnoreLabels          = $ignoreLabels
            MajorLabels           = $majorLabels
            MinorLabels           = $minorLabels
            PatchLabels           = $patchLabels
        } | Format-List | Out-String
    }

    Set-GitHubLogGroup 'Event information - JSON' {
        $githubEventJson = Get-Content $env:GITHUB_EVENT_PATH
        $githubEventJson | Format-List | Out-String
    }

    Set-GitHubLogGroup 'Event information - Object' {
        $githubEvent = $githubEventJson | ConvertFrom-Json
        $pull_request = $githubEvent.pull_request
        $githubEvent | Format-List | Out-String
    }

    Set-GitHubLogGroup 'Event information - Details' {
        $defaultBranchName = (gh repo view --json defaultBranchRef | ConvertFrom-Json | Select-Object -ExpandProperty defaultBranchRef).name
        $isPullRequest = $githubEvent.PSObject.Properties.Name -Contains 'pull_request'
        if (-not ($isPullRequest -or $whatIf)) {
            Write-Warning '⚠️ A release should not be created in this context. Exiting.'
            exit
        }
        $actionType = $githubEvent.action
        $isMerged = $pull_request.merged -eq 'True'
        $prIsClosed = $pull_request.state -eq 'closed'
        $prBaseRef = $pull_request.base.ref
        $prHeadRef = $pull_request.head.ref
        $targetIsDefaultBranch = $pull_request.base.ref -eq $defaultBranchName

        Write-Output '-------------------------------------------------'
        Write-Output "Default branch:                 [$defaultBranchName]"
        Write-Output "Is a pull request event:        [$isPullRequest]"
        Write-Output "Action type:                    [$actionType]"
        Write-Output "PR Merged:                      [$isMerged]"
        Write-Output "PR Closed:                      [$prIsClosed]"
        Write-Output "PR Base Ref:                    [$prBaseRef]"
        Write-Output "PR Head Ref:                    [$prHeadRef]"
        Write-Output "Target is default branch:       [$targetIsDefaultBranch]"
        Write-Output '-------------------------------------------------'
    }

    Set-GitHubLogGroup 'Pull request - details' {
        $pull_request | Format-List | Out-String
    }

    Set-GitHubLogGroup 'Pull request - Labels' {
        $labels = @()
        $labels += $pull_request.labels.name
        $labels | Format-List | Out-String
    }

    Set-GitHubLogGroup 'Calculate release type' {
        $createRelease = $isMerged -and $targetIsDefaultBranch
        $closedPullRequest = $prIsClosed -and -not $isMerged
        $createPrerelease = $labels -Contains 'prerelease' -and -not $createRelease -and -not $closedPullRequest
        $prereleaseName = $prHeadRef -replace '[^a-zA-Z0-9]'

        $ignoreRelease = ($labels | Where-Object { $ignoreLabels -contains $_ }).Count -gt 0
        if ($ignoreRelease) {
            Write-Output 'Ignoring release creation.'
            return
        }

        $majorRelease = ($labels | Where-Object { $majorLabels -contains $_ }).Count -gt 0
        $minorRelease = ($labels | Where-Object { $minorLabels -contains $_ }).Count -gt 0 -and -not $majorRelease
        $patchRelease = (
            ($labels | Where-Object { $patchLabels -contains $_ }
        ).Count -gt 0 -or $autoPatching) -and -not $majorRelease -and -not $minorRelease

        Write-Output '-------------------------------------------------'
        Write-Output "Create a release:               [$createRelease]"
        Write-Output "Create a prerelease:            [$createPrerelease]"
        Write-Output "Create a major release:         [$majorRelease]"
        Write-Output "Create a minor release:         [$minorRelease]"
        Write-Output "Create a patch release:         [$patchRelease]"
        Write-Output "Closed pull request:            [$closedPullRequest]"
        Write-Output '-------------------------------------------------'
    }

    Set-GitHubLogGroup 'Get latest version - GitHub' {
        $releases = gh release list --json 'createdAt,isDraft,isLatest,isPrerelease,name,publishedAt,tagName' | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            Write-Error 'Failed to list all releases for the repo.'
            exit $LASTEXITCODE
        }
        $releases | Select-Object -Property name, isPrerelease, isLatest, publishedAt | Format-Table | Out-String

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

    Set-GitHubLogGroup 'Get latest version - PSGallery' {
        $count = 5
        $delay = 10
        for ($i = 1; $i -le $count; $i++) {
            try {
                Write-Output "Finding module [$Name] in the PowerShell Gallery."
                $latest = Find-PSResource -Name $Name -Repository PSGallery -Verbose:$false
                Write-Output "$($latest | Format-Table | Out-String)"
                break
            } catch {
                if ($i -eq $count) {
                    Write-Warning "Failed to find the module [$Name] in the PowerShell Gallery."
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

    Set-GitHubLogGroup 'Get latest version - Manifest' {
        Add-PSModulePath -Path (Split-Path -Path $ModulePath -Parent)
        $manifestFilePath = Join-Path $ModulePath "$Name.psd1"
        Write-Output "Module manifest file path: [$manifestFilePath]"
        if (-not (Test-Path -Path $manifestFilePath)) {
            Write-Error "Module manifest file not found at [$manifestFilePath]"
            return
        }
        try {
            $manifestVersion = New-PSSemVer -Version (Test-ModuleManifest $manifestFilePath -Verbose:$false).Version
        } catch {
            if ([string]::IsNullOrEmpty($manifestVersion)) {
                Write-Warning 'Could not find the module version in the manifest. Using ''0.0.0'' as the version.'
                $manifestVersion = New-PSSemVer -Version '0.0.0'
            }
        }
        Write-Output '-------------------------------------------------'
        Write-Output 'Manifest version:'
        Write-Output $manifestVersion.ToString()
        Write-Output '-------------------------------------------------'
    }

    Set-GitHubLogGroup 'Get latest version' {
        Write-Output "GitHub:    [$($ghReleaseVersion.ToString())]"
        Write-Output "PSGallery: [$($psGalleryVersion.ToString())]"
        Write-Output "Manifest:  [$($manifestVersion.ToString())] (ignored)"
        $latestVersion = New-PSSemVer -Version ($psGalleryVersion, $ghReleaseVersion | Sort-Object -Descending | Select-Object -First 1)
        Write-Output '-------------------------------------------------'
        Write-Output 'Latest version:'
        Write-Output ($latestVersion | Format-Table | Out-String)
        Write-Output $latestVersion.ToString()
        Write-Output '-------------------------------------------------'
    }

    Set-GitHubLogGroup 'Calculate new version' {
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
            Write-Output 'Skipping release creation, exiting.'
            return
        }

        Write-Output "Partial new version: [$newVersion]"

        if ($createPrerelease) {
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
                    Name        = $Name
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
    Write-Output "New version is [$($newVersion.ToString())]"

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

    Set-GitHubLogGroup 'Install module dependencies' {
        Resolve-PSModuleDependency -ManifestFilePath $manifestFilePath
    }

    if ($createPrerelease -or $createRelease -or $whatIf) {
        Set-GitHubLogGroup 'Publish-ToPSGallery' {
            if ($createPrerelease) {
                $publishPSVersion = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)-$($newVersion.Prerelease)"
            } else {
                $publishPSVersion = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)"
            }
            $psGalleryReleaseLink = "https://www.powershellgallery.com/packages/$Name/$publishPSVersion"
            Write-Output "Publish module to PowerShell Gallery using [$APIKey]"
            if ($whatIf) {
                Write-Output "Publish-PSResource -Path $ModulePath -Repository PSGallery -ApiKey $APIKey"
            } else {
                try {
                    Publish-PSResource -Path $ModulePath -Repository PSGallery -ApiKey $APIKey
                } catch {
                    Write-Error $_.Exception.Message
                    exit $LASTEXITCODE
                }
            }
            if ($whatIf) {
                Write-Output (
                    "gh pr comment $($pull_request.number) -b 'Published to the" +
                    " PowerShell Gallery [$publishPSVersion]($psGalleryReleaseLink) has been created.'"
                )
            } else {
                Write-Host "::notice::Module [$Name - $publishPSVersion] published to the PowerShell Gallery."
                gh pr comment $pull_request.number -b "Module [$Name - $publishPSVersion]($psGalleryReleaseLink) published to the PowerShell Gallery."
                if ($LASTEXITCODE -ne 0) {
                    Write-Error 'Failed to comment on the pull request.'
                    exit $LASTEXITCODE
                }
            }
        }

        Set-GitHubLogGroup 'New-GitHubRelease' {
            Write-Output 'Create new GitHub release'
            if ($createPrerelease) {
                if ($whatIf) {
                    Write-Output "WhatIf: gh release create $newVersion --title $newVersion --target $prHeadRef --generate-notes --prerelease"
                } else {
                    $releaseURL = gh release create $newVersion --title $newVersion --target $prHeadRef --generate-notes --prerelease
                    if ($LASTEXITCODE -ne 0) {
                        Write-Error "Failed to create the release [$newVersion]."
                        exit $LASTEXITCODE
                    }
                }
            } else {
                if ($whatIf) {
                    Write-Output "WhatIf: gh release create $newVersion --title $newVersion --generate-notes"
                } else {
                    $releaseURL = gh release create $newVersion --title $newVersion --generate-notes
                    if ($LASTEXITCODE -ne 0) {
                        Write-Error "Failed to create the release [$newVersion]."
                        exit $LASTEXITCODE
                    }
                }
            }
            if ($whatIf) {
                Write-Output 'WhatIf: gh pr comment $pull_request.number -b "The release [$newVersion] has been created."'
            } else {
                gh pr comment $pull_request.number -b "GitHub release for $Name [$newVersion]($releaseURL) has been created."
                if ($LASTEXITCODE -ne 0) {
                    Write-Error 'Failed to comment on the pull request.'
                    exit $LASTEXITCODE
                }
            }
            Write-Host "::notice::Release created: [$newVersion]"
        }
    }

    Set-GitHubLogGroup 'List prereleases using the same name' {
        $prereleasesToCleanup = $releases | Where-Object { $_.tagName -like "*$prereleaseName*" }
        $prereleasesToCleanup | Select-Object -Property name, publishedAt, isPrerelease, isLatest | Format-Table | Out-String
    }

    if ((($closedPullRequest -or $createRelease) -and $autoCleanup) -or $whatIf) {
        Set-GitHubLogGroup "Cleanup prereleases for [$prereleaseName]" {
            foreach ($rel in $prereleasesToCleanup) {
                $relTagName = $rel.tagName
                Write-Output "Deleting prerelease:            [$relTagName]."
                if ($whatIf) {
                    Write-Output "WhatIf: gh release delete $($rel.tagName) --cleanup-tag --yes"
                } else {
                    gh release delete $rel.tagName --cleanup-tag --yes
                    if ($LASTEXITCODE -ne 0) {
                        Write-Error "Failed to delete release [$relTagName]."
                        exit $LASTEXITCODE
                    }
                }
            }
        }
    }

}
