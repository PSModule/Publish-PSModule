# Publish-PSModule

This GitHub Action is a part of the [PSModule framework](https://github.com/PSModule).

It publishes a **pre-versioned** PowerShell module artifact to the PowerShell Gallery and creates a matching GitHub
Release. The compressed module is also uploaded as a release asset so the GitHub Release page exposes the exact bytes
that were tested and pushed to the Gallery.

## Breaking change — v3.0.0

`Publish-PSModule` no longer calculates the next version or mutates the module manifest. The artifact passed in must
already contain the final `ModuleVersion` (and `Prerelease` tag, if any).

The following inputs were **removed**:

- `AutoPatching`
- `IncrementalPrerelease`
- `DatePrereleaseFormat`
- `VersionPrefix`
- `MajorLabels`, `MinorLabels`, `PatchLabels`, `IgnoreLabels`
- `ReleaseType`

To migrate, run [`PSModule/Resolve-PSModuleVersion`](https://github.com/PSModule/Resolve-PSModuleVersion) to compute
the version and pass it to [`PSModule/Build-PSModule`](https://github.com/PSModule/Build-PSModule) so the artifact is
stamped before it is tested. The publish action then ships that artifact without any post-build manipulation.

This makes the tested artifact identical to the published artifact (see
[PSModule/Process-PSModule#326](https://github.com/PSModule/Process-PSModule/issues/326)).

## What it does

1. Downloads the `module` artifact uploaded by `Build-PSModule`.
2. Reads `ModuleVersion` and `PrivateData.PSData.Prerelease` from the downloaded manifest.
3. Installs `RequiredModules` declared by the manifest.
4. Publishes the module to the PowerShell Gallery (`Publish-PSResource`).
5. Creates a GitHub Release with the same tag.
6. Zips the module folder and uploads it as a release asset (`<Name>-<Version>.zip`).
7. Optionally cleans up prerelease tags whose name matches the current PR branch.

## Inputs

| Name                       | Description                                                                                | Required | Default          |
| -------------------------- | ------------------------------------------------------------------------------------------ | -------- | ---------------- |
| `Name`                     | Name of the module. Defaults to the repository name.                                       | No       | Repository name  |
| `ModulePath`               | Path to the folder that contains the `<Name>/` module subdirectory (e.g. `outputs/module` must contain `outputs/module/<Name>/`). | No       | `outputs/module` |
| `APIKey`                   | PowerShell Gallery API key.                                                                | Yes      |                  |
| `AutoCleanup`              | Delete prerelease tags matching the PR branch after a stable release.                      | No       | `true`           |
| `WhatIf`                   | Log the changes that would be made without publishing, creating, or deleting anything.    | No       | `false`          |
| `WorkingDirectory`         | The working directory where the script will run from.                                      | No       | `.`              |
| `UsePRTitleAsReleaseName`  | Use the PR title as the release name (otherwise the version string is used).               | No       | `false`          |
| `UsePRBodyAsReleaseNotes`  | Use the PR body as the release notes (otherwise `--generate-notes` is used).               | No       | `true`           |
| `UsePRTitleAsNotesHeading` | Prefix the release notes with the PR title as an H1 heading linking to the PR.             | No       | `true`           |
