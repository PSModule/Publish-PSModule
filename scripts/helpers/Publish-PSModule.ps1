#REQUIRES -Modules Utilities, PowerShellGet, Microsoft.PowerShell.PSResourceGet

function Publish-PSModule {
    <#
        .SYNOPSIS
        Publishes a module to the PowerShell Gallery and GitHub Pages.

        .DESCRIPTION
        Publishes a module to the PowerShell Gallery and GitHub Pages.

        .EXAMPLE
        Publish-PSModule -Name 'PSModule.FX' -APIKey $env:PSGALLERY_API_KEY
    #>
    [CmdletBinding()]
    param(
        # Name of the module to process.
        [Parameter()]
        [string] $Name,

        # The path to the module to process.
        [Parameter(Mandatory)]
        [string] $ModulePath,

        # The path to the documentation to process.
        [Parameter(Mandatory)]
        [string] $DocsPath,

        # The API key for the destination repository.
        [Parameter(Mandatory)]
        [string] $APIKey
    )

    #region Set configuration
    Start-LogGroup 'Set configuration'
    if (-not (Test-Path -Path $env:GITHUB_ACTION_INPUT_ConfigurationFile -PathType Leaf)) {
        Write-Output "Configuration file not found at [$env:GITHUB_ACTION_INPUT_ConfigurationFile]"
    } else {
        Write-Output "Reading from configuration file [$env:GITHUB_ACTION_INPUT_ConfigurationFile]"
        $configuration = ConvertFrom-Yaml -Yaml (Get-Content $env:GITHUB_ACTION_INPUT_ConfigurationFile -Raw)
    }

    $autoCleanup = ($configuration.AutoCleanup | IsNotNullOrEmpty) ? $configuration.AutoCleanup -eq 'true' : $env:GITHUB_ACTION_INPUT_AutoCleanup -eq 'true'
    $autoPatching = ($configuration.AutoPatching | IsNotNullOrEmpty) ? $configuration.AutoPatching -eq 'true' : $env:GITHUB_ACTION_INPUT_AutoPatching -eq 'true'
    $createMajorTag = ($configuration.CreateMajorTag | IsNotNullOrEmpty) ? $configuration.CreateMajorTag -eq 'true' : $env:GITHUB_ACTION_INPUT_CreateMajorTag -eq 'true'
    $createMinorTag = ($configuration.CreateMinorTag | IsNotNullOrEmpty) ? $configuration.CreateMinorTag -eq 'true' : $env:GITHUB_ACTION_INPUT_CreateMinorTag -eq 'true'
    $datePrereleaseFormat = ($configuration.DatePrereleaseFormat | IsNotNullOrEmpty) ? $configuration.DatePrereleaseFormat : $env:GITHUB_ACTION_INPUT_DatePrereleaseFormat
    $incrementalPrerelease = ($configuration.IncrementalPrerelease | IsNotNullOrEmpty) ? $configuration.IncrementalPrerelease -eq 'true' : $env:GITHUB_ACTION_INPUT_IncrementalPrerelease -eq 'true'
    $versionPrefix = ($configuration.VersionPrefix | IsNotNullOrEmpty) ? $configuration.VersionPrefix : $env:GITHUB_ACTION_INPUT_VersionPrefix
    $whatIf = ($configuration.WhatIf | IsNotNullOrEmpty) ? $configuration.WhatIf -eq 'true' : $env:GITHUB_ACTION_INPUT_WhatIf -eq 'true'

    $ignoreLabels = (($configuration.IgnoreLabels | IsNotNullOrEmpty) ? $configuration.IgnoreLabels : $env:GITHUB_ACTION_INPUT_IgnoreLabels) -split ',' | ForEach-Object { $_.Trim() }
    $majorLabels = (($configuration.MajorLabels | IsNotNullOrEmpty) ? $configuration.MajorLabels : $env:GITHUB_ACTION_INPUT_MajorLabels) -split ',' | ForEach-Object { $_.Trim() }
    $minorLabels = (($configuration.MinorLabels | IsNotNullOrEmpty) ? $configuration.MinorLabels : $env:GITHUB_ACTION_INPUT_MinorLabels) -split ',' | ForEach-Object { $_.Trim() }
    $patchLabels = (($configuration.PatchLabels | IsNotNullOrEmpty) ? $configuration.PatchLabels : $env:GITHUB_ACTION_INPUT_PatchLabels) -split ',' | ForEach-Object { $_.Trim() }

    Write-Output '-------------------------------------------------'
    Write-Output "Auto cleanup enabled:           [$autoCleanup]"
    Write-Output "Auto patching enabled:          [$autoPatching]"
    Write-Output "Create major tag enabled:       [$createMajorTag]"
    Write-Output "Create minor tag enabled:       [$createMinorTag]"
    Write-Output "Date-based prerelease format:   [$datePrereleaseFormat]"
    Write-Output "Incremental prerelease enabled: [$incrementalPrerelease]"
    Write-Output "Version prefix:                 [$versionPrefix]"
    Write-Output "What if mode:                   [$whatIf]"
    Write-Output ''
    Write-Output "Ignore labels:                  [$($ignoreLabels -join ', ')]"
    Write-Output "Major labels:                   [$($majorLabels -join ', ')]"
    Write-Output "Minor labels:                   [$($minorLabels -join ', ')]"
    Write-Output "Patch labels:                   [$($patchLabels -join ', ')]"
    Write-Output '-------------------------------------------------'
    Stop-LogGroup
    #endregion Set configuration

    #region Get event information
    Start-LogGroup 'Event information - JSON'
    $githubEventJson = Get-Content $env:GITHUB_EVENT_PATH
    $githubEventJson | Format-List
    Stop-LogGroup

    Start-LogGroup 'Event information - Object'
    $githubEvent = $githubEventJson | ConvertFrom-Json
    $pull_request = $githubEvent.pull_request
    $githubEvent | Format-List
    Stop-LogGroup

    $defaultBranchName = (gh repo view --json defaultBranchRef | ConvertFrom-Json | Select-Object -ExpandProperty defaultBranchRef).name
    $isPullRequest = $githubEvent.PSObject.Properties.Name -Contains 'pull_request'
    if (-not ($isPullRequest -or $whatIf)) {
        Write-Warning '⚠️ A release should not be created in this context. Exiting.'
        exit
    }
    $actionType = $githubEvent.action
    $isMerged = ($pull_request.merged).ToString() -eq 'True'
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

    Start-LogGroup 'Pull request - details'
    $pull_request | Format-List
    Stop-LogGroup

    Start-LogGroup 'Pull request - Labels'
    $labels = @()
    $labels += $pull_request.labels.name
    $labels | Format-List
    Stop-LogGroup
    #endregion Get event information

    #region Calculate release type
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
    $patchRelease = ($labels | Where-Object { $patchLabels -contains $_ }).Count -gt 0 -and -not $majorRelease -and -not $minorRelease

    Write-Output '-------------------------------------------------'
    Write-Output "Create a release:               [$createRelease]"
    Write-Output "Create a prerelease:            [$createPrerelease]"
    Write-Output "Create a major release:         [$majorRelease]"
    Write-Output "Create a minor release:         [$minorRelease]"
    Write-Output "Create a patch release:         [$patchRelease]"
    Write-Output "Closed pull request:            [$closedPullRequest]"
    Write-Output '-------------------------------------------------'
    #endregion Calculate release type

    #region Get GitHub releases
    Start-LogGroup 'Get Github releases'
    $releases = gh release list --json 'createdAt,isDraft,isLatest,isPrerelease,name,publishedAt,tagName' | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Failed to list all releases for the repo.'
        exit $LASTEXITCODE
    }
    $releases | Select-Object -Property name, isPrerelease, isLatest, publishedAt | Format-Table
    Stop-LogGroup
    #endregion Get GitHub releases

    #region Get GitHub latest version
    Start-LogGroup 'Get GitHub latest version'
    $latestRelease = $releases | Where-Object { $_.isLatest -eq $true }
    $latestRelease | Format-List
    $ghReleaseVersionString = $latestRelease.tagName
    if ($ghReleaseVersionString | IsNotNullOrEmpty) {
        $ghReleaseVersion = $ghReleaseVersionString | ConvertTo-SemVer
        Write-Output '-------------------------------------------------'
        Write-Output 'Latest version:'
        $ghReleaseVersion | Format-Table
        $ghReleaseVersion = $ghReleaseVersion.ToString()
    }
    Write-Output '-------------------------------------------------'
    Write-Output "Latest version:                 [$ghReleaseVersion]"
    Write-Output '-------------------------------------------------'
    Stop-LogGroup

    #endregion Get GitHub latest version

    #region Get target location (PSGallery) latest version.
    Start-LogGroup 'Get target location (PSGallery) latest version'
    try {
        $psGalleryVersion = [PSSemVer](Find-PSResource -Name $Name -Repository PSGallery -Verbose:$false).Version
    } catch {
        Write-Warning 'Could not find module online.'
    }
    Write-Warning "Online: [$($psGalleryVersion.ToString())]"
    Stop-LogGroup
    #endregion Get target location (PSGallery) latest version.

    #region Get module manifest version.
    Start-LogGroup 'Get module manifest version'
    Add-PSModulePath -Path (Split-Path -Path $ModulePath -Parent)
    $manifestFilePath = Join-Path $ModulePath "$Name.psd1"
    Write-Verbose "Module manifest file path: [$manifestFilePath]"
    if (-not (Test-Path -Path $manifestFilePath)) {
        Write-Error "Module manifest file not found at [$manifestFilePath]"
        return
    }
    $manifestVersion = [PSSemVer](Test-ModuleManifest $manifestFilePath -Verbose:$false).Version
    Write-Warning "Manifest version: [$($manifestVersion.ToString())]"
    Stop-LogGroup
    #endregion Get module manifest version.

    #region Calculate new version
    Start-LogGroup 'Calculate new version'

    # - Mixed mode
    #   - Take the highest version from GH, PSGallery and manifest
    Write-Warning "PSGallery: [$($psGalleryVersion.ToString())]"
    Write-Warning "Manifest:  [$($manifestVersion.ToString())]"
    Write-Warning "GitHub:    [$($ghReleaseVersion.ToString())]"
    $newVersion = $psGalleryVersion, $manifestVersion, $ghReleaseVersion | Sort-Object -Descending | Select-Object -First 1

    # - GitHub mode
    #   - Take the version number from the release
    # - PSGallery mode
    #   - Take the version number from the PSGallery

    # - Increment based on label on PR
    $newVersion.Prefix = $versionPrefix
    if ($majorRelease) {
        Write-Output 'Incrementing major version.'
        $newVersion.BumpMajor()
    } elseif ($minorRelease) {
        Write-Output 'Incrementing minor version.'
        $newVersion.BumpMinor()
    } elseif ($patchRelease -or $autoPatching) {
        Write-Output 'Incrementing patch version.'
        $newVersion.BumpPatch()
    } else {
        Write-Output 'Skipping release creation, exiting.'
        return
    }

    # - Manifest mode
    #   - Take the version number from the manifest directly
    Write-Output "Partial new version: [$newVersion]"

    if ($createPrerelease) {
        Write-Output "Adding a prerelease tag to the version using the branch name [$prereleaseName]."
        $newVersion.Prerelease = $prereleaseName
        Write-Output "Partial new version: [$newVersion]"

        if ($datePrereleaseFormat | IsNotNullOrEmpty) {
            Write-Output "Using date-based prerelease: [$datePrereleaseFormat]."
            $newVersion.Prerelease += ".$(Get-Date -Format $datePrereleaseFormat)"
            Write-Output "Partial new version: [$newVersion]"
        }

        if ($incrementalPrerelease) {
            $newVersion.BumpPrereleaseNumber()
        }
    }
    Stop-LogGroup
    Write-Output '-------------------------------------------------'
    Write-Output "New version:                    [$newVersion]"
    Write-Output '-------------------------------------------------'

    #endregion Calculate new version

    #region Update module manifest
    Start-LogGroup 'Update module manifest'
    if ($createPrerelease) {
        Write-Verbose "Prerelease is: [$prereleaseName]"
        # if ($newVersion -ge [PSSemVer]'1.0.0') {
        #     Write-Verbose "Version is greater than 1.0.0 -> Update-PSModuleManifest with prerelease [$prereleaseName]"
        Update-ModuleManifest -Path $manifestFilePath -Prerelease $prereleaseName -ErrorAction Continue
        # }
    }
    Write-Verbose 'Bump module version -> module metadata: Update-ModuleMetadata'
    $manifestNewVersion = "$($newVersion.Major).$($newVersion.Minor).$($newVersion.Patch)"
    Update-ModuleManifest -Path $manifestFilePath -ModuleVersion $manifestNewVersion -ErrorAction Continue
    Stop-LogGroup

    #region Format manifest file
    Start-LogGroup 'Format manifest file - Before format'
    Show-FileContent -Path $manifestFilePath
    Stop-LogGroup

    Start-LogGroup 'Format manifest file - Remove comments'
    $manifestContent = Get-Content -Path $manifestFilePath
    $manifestContent = $manifestContent | ForEach-Object { $_ -replace '#.*' }
    $manifestContent | Out-File -FilePath $manifestFilePath -Encoding utf8BOM -Force
    Show-FileContent -Path $manifestFilePath
    Stop-LogGroup

    Start-LogGroup 'Format manifest file - Removing trailing whitespace'
    $manifestContent = Get-Content -Path $manifestFilePath
    $manifestContent = $manifestContent | ForEach-Object { $_.TrimEnd() }
    $manifestContent | Out-File -FilePath $manifestFilePath -Encoding utf8BOM -Force
    Show-FileContent -Path $manifestFilePath
    Stop-LogGroup

    Start-LogGroup 'Format manifest file - Remove blank lines'
    $manifestContent = Get-Content -Path $manifestFilePath
    $manifestContent = $manifestContent | Where-Object { -not [string]::IsNullOrEmpty($_) }
    $manifestContent | Out-File -FilePath $manifestFilePath -Encoding utf8BOM -Force
    Show-FileContent -Path $manifestFilePath
    Stop-LogGroup

    Start-LogGroup 'Format manifest file - Format'
    $manifestContent = Get-Content -Path $manifestFilePath -Raw
    $settings = (Join-Path -Path $PSScriptRoot 'PSScriptAnalyzer.Tests.psd1')
    Invoke-Formatter -ScriptDefinition $manifestContent -Settings $settings |
        Out-File -FilePath $manifestFilePath -Encoding utf8BOM -Force
    Show-FileContent -Path $manifestFilePath
    Stop-LogGroup

    #TODO: Add way to normalize string arrays like filelist and command lists

    Start-LogGroup 'Format manifest file - Result'
    Show-FileContent -Path $manifestFilePath
    Stop-LogGroup
    #endregion Format manifest file

    #endregion Update module manifest

    #region Create releases
    if ($createPrerelease -or $createRelease -or $whatIf) {
        #region Publish-ToPSGallery
        Start-LogGroup 'Publish-ToPSGallery'
        Write-Verbose "Publish module to PowerShell Gallery using [$APIKey]"
        if ($whatIf) {
            Write-Verbose "Publish-PSResource -Path $ModulePath -Repository PSGallery -ApiKey $APIKey -Verbose"
        } else {
            try {
                Publish-PSResource -Path $ModulePath -Repository PSGallery -ApiKey $APIKey -Verbose
            } catch {
                Write-Error 'Failed to publish the module to the PowerShell Gallery.'
                exit $LASTEXITCODE
            }
        }
        if ($whatIf) {
            Write-Output "gh pr comment $($pull_request.number) -b 'Published to the PowerShell Gallery [$newVersion]($releaseURL) has been created.'"
        } else {
            Write-Output "::notice::Module [$Name - $manifestNewVersion] published to the PowerShell Gallery."
            gh pr comment $pull_request.number -b "Module [$Name - $manifestNewVersion] published to the PowerShell Gallery."
            if ($LASTEXITCODE -ne 0) {
                Write-Error 'Failed to comment on the pull request.'
                exit $LASTEXITCODE
            }
        }
        Stop-LogGroup
        #endregion Publish-ToPSGallery

        #region New-GitHubRelease
        Start-LogGroup 'New-GitHubRelease'
        Write-Verbose 'Create new GitHub release'
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
        Write-Output "::notice::Release created: [$newVersion]"
        Stop-LogGroup
        #endregion New-GitHubRelease

        #region Publish-Docs
        Start-LogGroup "Publish docs - [$DocsPath]"
        Write-Verbose 'Publish docs to GitHub Pages'
        Write-Verbose 'Update docs path: Update-ModuleMetadata'
        Stop-LogGroup
        #endregion Publish-Docs
    }
    #endregion Create releases

    #region Cleanup prereleases
    Start-LogGroup 'List prereleases using the same name'
    $prereleasesToCleanup = $releases | Where-Object { $_.tagName -like "*$prereleaseName*" }
    $prereleasesToCleanup | Select-Object -Property name, publishedAt, isPrerelease, isLatest | Format-Table
    Stop-LogGroup

    if ((($closedPullRequest -or $createRelease) -and $autoCleanup) -or $whatIf) {
        Start-LogGroup "Cleanup prereleases for [$prereleaseName]"
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
        Stop-LogGroup
    }
    #endregion Cleanup prereleases

}
