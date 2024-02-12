# Auto-Release

Automatically creates releases based on pull requests and labels.

## Specifications and practices

Auto-Release follows:
Test

- [SemVer 2.0.0 specifications](https://semver.org)
- [GitHub Flow specifications](https://docs.github.com/en/get-started/using-github/github-flow)
- [Continiuous Delivery practices](https://en.wikipedia.org/wiki/Continuous_delivery)

## Usage

The action have the following parameters:

| Parameter | Description | Default | Required |
| --- | --- | --- | --- |
| `AutoPatching` | Control wether to automatically handle patches. If disabled, the action will only create a patch release if the pull request has a 'patch' label. | `true` | false |
| `IncrementalPrerelease` | Control wether to automatically increment the prerelease number. If disabled, the action will ensure only one prerelease exists for a given branch. | `true` | false |
| `VersionPrefix` | The prefix to use for the version number. | `v` | false |

### Example
Add a workflow in you repository using the following example:

```yaml
name: Auto-Release

on:
  pull_request:
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
