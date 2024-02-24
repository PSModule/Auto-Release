#REQUIRES -Modules Utilities, powershell-yaml

[CmdletBinding()]
param()

Start-LogGroup 'Environment variables'
Get-ChildItem -Path Env: | Select-Object Name, Value | Sort-Object Name | Format-Table -AutoSize
Stop-LogGroup

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

Start-LogGroup 'Event information - JSON'
$githubEventJson = Get-Content $env:GITHUB_EVENT_PATH
$githubEventJson | Format-List
Stop-LogGroup

Start-LogGroup 'Event information - Object'
$githubEvent = $githubEventJson | ConvertFrom-Json
$pull_request = $githubEvent.pull_request
$githubEvent | Format-List
Stop-LogGroup

$isPullRequest = $githubEvent.PSObject.Properties.Name -Contains 'pull_request'
if (-not ($isPullRequest -or $whatIf)) {
    'A release should not be created in this context. Exiting.'
    return
}

Write-Output '-------------------------------------------------'
Write-Output "Is a pull request event:        [$isPullRequest]"
Write-Output "Action type:                    [$($githubEvent.action)]"
Write-Output "PR Merged:                      [$($pull_request.merged)]"
Write-Output "PR State:                       [$($pull_request.state)]"
Write-Output "PR Base Ref:                    [$($pull_request.base.ref)]"
Write-Output "PR Head Ref:                    [$($pull_request.head.ref)]"
Write-Output '-------------------------------------------------'
$preReleaseName = $pull_request.head.ref -replace '[^a-zA-Z0-9]', ''

Start-LogGroup 'Pull request - details'
$pull_request | Format-List
Stop-LogGroup

Start-LogGroup 'Pull request - Labels'
$labels = @()
$labels += $pull_request.labels.name
$labels | Format-List
Stop-LogGroup

$createRelease = $pull_request.base.ref -eq 'main' -and ($pull_request.merged).ToString() -eq 'True'
$closedPullRequest = $pull_request.state -eq 'closed' -and ($pull_request.merged).ToString() -eq 'False'
$preRelease = $labels -Contains 'prerelease'
$createPrerelease = $preRelease -and -not $createRelease -and -not $closedPullRequest

$ignoreRelease = ($labels | Where-Object { $ignoreLabels -contains $_ }).Count -gt 0
$majorRelease = ($labels | Where-Object { $majorLabels -contains $_ }).Count -gt 0
$minorRelease = ($labels | Where-Object { $minorLabels -contains $_ }).Count -gt 0 -and -not $majorRelease
$patchRelease = ($labels | Where-Object { $patchLabels -contains $_ }).Count -gt 0 -and -not $majorRelease -and -not $minorRelease

if ($ignoreRelease) {
    Write-Output 'Ignoring release creation.'
    return
}

Write-Output '-------------------------------------------------'
Write-Output "Create a release:               [$createRelease]"
Write-Output "Create a prerelease:            [$createPrerelease]"
Write-Output "Create a major release:         [$majorRelease]"
Write-Output "Create a minor release:         [$minorRelease]"
Write-Output "Create a patch release:         [$patchRelease]"
Write-Output "Closed pull request:            [$closedPullRequest]"
Write-Output '-------------------------------------------------'

Start-LogGroup 'Get releases'
$releases = gh release list --json 'createdAt,isDraft,isLatest,isPrerelease,name,publishedAt,tagName' | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Error 'Failed to list all releases for the repo.'
    exit $LASTEXITCODE
}
$releases | Select-Object -Property name, isPrerelease, isLatest, publishedAt | Format-Table
Stop-LogGroup

Start-LogGroup 'Get latest version'
$latestRelease = $releases | Where-Object { $_.isLatest -eq $true }
$latestRelease | Format-List
$latestVersionString = $latestRelease.tagName
if ($latestVersionString | IsNotNullOrEmpty) {
    $latestVersion = $latestVersionString | ConvertTo-SemVer
    Write-Output '-------------------------------------------------'
    Write-Output 'Latest version:'
    $latestVersion | Format-Table
    $latestVersion = $latestVersion.ToString()
}
Stop-LogGroup

Write-Output '-------------------------------------------------'
Write-Output "Latest version:                 [$latestVersion]"
Write-Output '-------------------------------------------------'

if ($createPrerelease -or $createRelease -or $whatIf) {
    Start-LogGroup 'Calculate new version'
    $latestVersion = New-SemVer -Version $latestVersion
    $newVersion = New-SemVer -Version $latestVersion
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

    Write-Output "Partly new version: [$newVersion]"

    if ($createPrerelease) {
        Write-Output "Adding a prerelease tag to the version using the branch name [$preReleaseName]."
        $newVersion.Prerelease = $preReleaseName
        Write-Output "Partly new version: [$newVersion]"

        if ($datePrereleaseFormat | IsNotNullOrEmpty) {
            Write-Output "Using date-based prerelease: [$datePrereleaseFormat]."
            $newVersion.Prerelease += ".$(Get-Date -Format $datePrereleaseFormat)"
            Write-Output "Partly new version: [$newVersion]"
        }

        if ($incrementalPrerelease) {
            $prereleases = $releases | Where-Object { $_.tagName -like "$newVersion*" }
            $prereleases |
                Select-Object -Property @{n = 'number'; e = { [int](($_.tagName -Split '\.')[-1]) } }, name, publishedAt, isPrerelease, isLatest |
                Format-Table

            if ($prereleases.count -gt 0) {
                $latestPrereleaseVersion = $prereleases[0].tagName | ConvertTo-SemVer | Select-Object -ExpandProperty Prerelease
                Write-Output "Latest prerelease:              [$latestPrereleaseVersion]"
                $latestPrereleaseNumber = [int]($latestPrereleaseVersion -Split '\.')[-1]
                Write-Output "Latest prerelease number:       [$latestPrereleaseNumber]"
            }

            $newPrereleaseNumber = 0 + $latestPrereleaseNumber + 1
            $newVersion.Prerelease += ".$newPrereleaseNumber"
        }
    }
    Stop-LogGroup
    Write-Output '-------------------------------------------------'
    Write-Output "New version:                    [$newVersion]"
    Write-Output '-------------------------------------------------'

    Start-LogGroup "Create new release [$newVersion]"
    if ($createPrerelease) {
        $releaseExists = $releases.tagName -Contains $newVersion
        if ($releaseExists -and -not $incrementalPrerelease) {
            Write-Output 'Release already exists, recreating.'
            if ($whatIf) {
                Write-Output "WhatIf: gh release delete $newVersion --cleanup-tag --yes"
            } else {
                gh release delete $newVersion --cleanup-tag --yes
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to delete the release [$newVersion]."
                    exit $LASTEXITCODE
                }
            }
        }

        if ($whatIf) {
            Write-Output "WhatIf: gh release create $newVersion --title $newVersion --target $($pull_request.head.ref) --generate-notes --prerelease"
        } else {
            gh release create $newVersion --title $newVersion --target $pull_request.head.ref --generate-notes --prerelease
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to create the release [$newVersion]."
                exit $LASTEXITCODE
            }
        }

        if ($whatIf) {
            Write-Output 'WhatIf: gh pr comment $pull_request.number -b "The release [$newVersion] has been created."'
        } else {
            gh pr comment $pull_request.number -b "The release [$newVersion] has been created."
            if ($LASTEXITCODE -ne 0) {
                Write-Error 'Failed to comment on the pull request.'
                exit $LASTEXITCODE
            }
        }
    } else {
        if ($whatIf) {
            Write-Output "WhatIf: gh release create $newVersion --title $newVersion --generate-notes"
        } else {
            gh release create $newVersion --title $newVersion --generate-notes
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to create the release [$newVersion]."
                exit $LASTEXITCODE
            }
        }

        if ($createMajorTag) {
            $majorTag = ('{0}{1}' -f $versionPrefix, $major)
            if ($whatIf) {
                Write-Output "WhatIf: git tag -f $majorTag 'main'"
            } else {
                git tag -f $majorTag 'main'
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to create major tag [$majorTag]."
                    exit $LASTEXITCODE
                }
            }
        }

        if ($createMinorTag) {
            $minorTag = ('{0}{1}.{2}' -f $versionPrefix, $major, $minor)
            if ($whatIf) {
                Write-Output "WhatIf: git tag -f $minorTag 'main'"
            } else {
                git tag -f $minorTag 'main'
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to create minor tag [$minorTag]."
                    exit $LASTEXITCODE
                }
            }
        }

        if ($whatIf) {
            Write-Output 'WhatIf: git push origin --tags --force'
        } else {
            git push origin --tags --force
            if ($LASTEXITCODE -ne 0) {
                Write-Error 'Failed to push tags.'
                exit $LASTEXITCODE
            }
        }
        Stop-LogGroup
    }
    Write-Output "::notice::Release created: [$newVersion]"
} else {
    Write-Output 'Skipping release creation.'
}

Start-LogGroup 'List prereleases using the same name'
$prereleasesToCleanup = $releases | Where-Object { $_.tagName -like "*$preReleaseName*" }
$prereleasesToCleanup | Select-Object -Property name, publishedAt, isPrerelease, isLatest | Format-Table
Stop-LogGroup

if (($closedPullRequest -or $createRelease) -and $autoCleanup -or $whatIf) {
    Write-Output "::group::Cleanup prereleases for [$preReleaseName]"
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
