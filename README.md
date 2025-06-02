# Publish-PSModule

Creates a GitHub release and publishes the PowerShell module to the PowerShell Gallery.

This GitHub Action is a part of the [PSModule framework](https://github.com/PSModule). It is recommended to use the [Process-PSModule workflow](https://github.com/PSModule/Process-PSModule) to automate the whole process of managing the PowerShell module.

## Specifications and practices

Publish-PSModule follows:

- [SemVer 2.0.0 specifications](https://semver.org)
- [GitHub Flow specifications](https://docs.github.com/en/get-started/using-github/github-flow)
- [Continiuous Delivery practices](https://en.wikipedia.org/wiki/Continuous_delivery)

... and supports the following practices in the PSModule framework:

- [PowerShell publishing guidelines](https://learn.microsoft.com/en-us/powershell/gallery/concepts/publishing-guidelines?view=powershellget-3.x)

## How it works

The workflow will trigger on pull requests to the repositorys default branch.
When the pull request is opened, the action will decide what to do based on labels on the pull request.

It will get the latest release version by looking up the versions in GitHub releases, PowerShell Gallery and the module manifest.
The next version is then determined by the labels on the pull request. If a prerelease label is found, the action will create a
prerelease with the branch name (in normalized form) as the prerelease name. By defualt, the following labels are used:

- For a major release, and increasing the first number in the version use:
  - `major`
  - `breaking`
- For a minor release, and increasing the second number in the version.
  - `minor`
  - `feature`
- For a patch release, and increases the third number in the version.
  - `patch`
  - `fix`

The types of labels used for the types of prereleases can be configured using the `MajorLabels`, `MinorLabels` and `PatchLabels`
parameters/settings. See the [Usage](#usage) section for more information.

When a pull request is merged into the default branch, the action will create a release based on the labels and clean up any previous
prereleases that was created.

## Usage

The action can be configured using the following settings:

| Name | Description | Required | Default |
| --- | --- | --- | --- |
| `Name` | Name of the module to publish. Defaults to the repository name. | `false` | |
| `ModulePath` | Path to the folder where the module to publish is located. | `false` | `outputs/modules` |
| `APIKey` | PowerShell Gallery API Key. | `true` | |
| `AutoCleanup`| Control wether to automatically cleanup prereleases. If disabled, the action will not remove any prereleases. | `false` | `true` |
| `AutoPatching` | Control wether to automatically handle patches. If disabled, the action will only create a patch release if the pull request has a 'patch' label. | `false` | `true` |
| `DatePrereleaseFormat` | The format to use for the prerelease number using [.NET DateTime format strings](https://learn.microsoft.com/en-us/dotnet/standard/base-types/standard-date-and-time-format-strings). | `false` | `''` |
| `IncrementalPrerelease` | Control wether to automatically increment the prerelease number. If disabled, the action will ensure only one prerelease exists for a given branch. | `false` | `true` |
| `VersionPrefix` | The prefix to use for the version number. | `false` | `v` |
| `MajorLabels` | A comma separated list of labels that trigger a major release. | `false` | `major, breaking` |
| `MinorLabels` | A comma separated list of labels that trigger a minor release. | `false` | `minor, feature` |
| `PatchLabels` | A comma separated list of labels that trigger a patch release. | `false` | `patch, fix` |
| `IgnoreLabels` | A comma separated list of labels that do not trigger a release. | `false` | `NoRelease` |
| `WhatIf` | Control wether to simulate the action. If enabled, the action will not create any releases. Used for testing. | `false` | `false` |
| `WorkingDirectory` | The working directory where the script runs. | `'false'`    | `'.'` |

## Example

```yaml
name: Publish-PSModule

on: [pull_request]

jobs:
  Publish-PSModule:
    name: Publish-PSModule
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repo
        uses: actions/checkout@v4

      - name: Initialize environment
        uses: PSModule/Initialize-PSModule@main

      - name: Publish-PSModule
        uses: PSModule/Publish-PSModule@main
        env:
          GITHUB_TOKEN: ${{ github.token }}
        with:
          APIKey: ${{ secrets.APIKEY }}
```

## Permissions

The action requires the following permissions:

If running the action in a restrictive mode, the following permissions needs to be granted to the action:

```yaml
permissions:
  contents: write # Required to create releases
  pull-requests: write # Required to create comments on the PRs
```
