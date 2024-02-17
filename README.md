# Auto-Release

Automatically creates releases based on pull requests and labels.

## Specifications and practices

Auto-Release follows:

- [SemVer 2.0.0 specifications](https://semver.org)
- [GitHub Flow specifications](https://docs.github.com/en/get-started/using-github/github-flow)
- [Continiuous Delivery practices](https://en.wikipedia.org/wiki/Continuous_delivery)


## How it works

The workflow will trigger on pull requests to the main branch.

The following labels will inform the action what kind of release to create:
- For a major release, and increasing the first number in the version use:
  - `major`
  - `breaking`
- For a minor release, and increasing the second number in the version.
  - `minor`
  - `feature`
  - `improvement`
  - `enhancement`
- For a patch release, and increases the third number in the version.
  - `patch`
  - `bug`
  - `fix`

When a pull request is closed, the action will create a release based on the labels and clean up any previous prereleases that was created.


## Usage

The action have the following parameters:

| Parameter | Description | Default | Required |
| --- | --- | --- | --- |
| `AutoCleanup`| Control wether to automatically cleanup prereleases. If disabled, the action will not remove any prereleases. | `true` | false |
| `AutoPatching` | Control wether to automatically handle patches. If disabled, the action will only create a patch release if the pull request has a 'patch' label. | `true` | false |
| `ConfigurationFile` | The path to the configuration file. Settings in the configuration file take precedence over the action inputs. | `.github\auto-release.yml` | false |
| `CreateMajorTag` | Control wether to create a tag for major releases. | `true` | false |
| `CreateMinorTag` | Control wether to create a tag for minor releases. | `true` | false |
| `DatePrereleaseFormat` | The format to use for the prerelease number using [.NET DateTime format strings](https://learn.microsoft.com/en-us/dotnet/standard/base-types/standard-date-and-time-format-strings). | `''` | false |
| `IncrementalPrerelease` | Control wether to automatically increment the prerelease number. If disabled, the action will ensure only one prerelease exists for a given branch. | `true` | false |
| `MajorLabels` | The labels to use for major releases. | `major, breaking` | false |
| `MinorLabels` | The labels to use for minor releases. | `minor, feature, improvement` | false |
| `PatchLabels` | The labels to use for patch releases. | `patch, fix, bug` | false |
| `VersionPrefix` | The prefix to use for the version number. | `v` | false |

### Configuration file

The configuration file is a YAML file that can be used to configure the action.
The file can be placed in the `.github` directory of the repository and named `auto-release.yml`.
The file can be used to configure the action using the same parameters as the action inputs.

```yaml
DatePrereleaseFormat: 'yyyyMMddHHmm'
IncrementalPrerelease: false
VersionPrefix: ''
```

This example uses the date format for the prerelease, disables the incremental prerelease and removes the version prefix.

## Example
Add a workflow in you repository using the following example:

```yaml
name: Auto-Release

on:
  pull_request_target:
    branches:
      - main
    types:
      - closed
      - opened
      - reopened
      - synchronize
      - labeled

concurrency:
  group: ${{ github.workflow }}

jobs:
  Auto-Release:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Auto-Release
        uses: PSModule/Auto-Release@v1
        env:
          GH_TOKEN: ${{ github.token }} # Used for GitHub CLI authentication
```
