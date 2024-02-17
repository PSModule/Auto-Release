Write-Output '::group::Install - Utilities'
Install-PSResource -Name Utilities -TrustRepository
Write-Output '-------------------------------------------------'
Get-PSResource -Name Utilities | Format-Table
Write-Output '-------------------------------------------------'
Write-Output 'Get commands'
Get-Command -Module Utilities | Format-Table
Write-Output '-------------------------------------------------'
Write-Output 'Get aliases'
Get-Alias | Where-Object Source -EQ 'Utilities' | Format-Table
Write-Output '-------------------------------------------------'
Write-Output '::endgroup::'

Write-Output '::group::Install - powershell-yaml'
Install-PSResource -Name powershell-yaml -TrustRepository
Write-Output '-------------------------------------------------'
Get-PSResource -Name powershell-yaml | Format-Table
Write-Output '-------------------------------------------------'
Write-Output 'Get commands'
Get-Command -Module powershell-yaml | Format-Table
Write-Output '-------------------------------------------------'
Write-Output 'Get aliases'
Get-Alias | Where-Object Source -EQ 'powershell-yaml' | Format-Table
Write-Output '-------------------------------------------------'
Write-Output '::endgroup::'

Write-Output '::group::Environment variables'
Get-ChildItem -Path Env: | Select-Object Name, Value | Sort-Object Name | Format-Table -AutoSize
Write-Output '::endgroup::'

Write-Output '::group::Set configuration'
if (-not (Test-Path -Path $env:ConfigurationFile -PathType Leaf)) {
    Write-Output "Configuration file not found at [$env:ConfigurationFile]"
} else {
    Write-Output "Reading from configuration file [$env:ConfigurationFile]"
    $configuration = ConvertFrom-Yaml -Yaml (Get-Content $env:ConfigurationFile -Raw)
}

$autoCleanup = ($configuration.AutoCleanup | IsNotNullOrEmpty) ? $configuration.AutoCleanup -eq 'true' : $env:AutoCleanup -eq 'true'
$autoPatching = ($configuration.AutoPatching | IsNotNullOrEmpty) ? $configuration.AutoPatching -eq 'true' : $env:AutoPatching -eq 'true'
$createMajorTag = ($configuration.CreateMajorTag | IsNotNullOrEmpty) ? $configuration.CreateMajorTag -eq 'true' : $env:CreateMajorTag -eq 'true'
$createMinorTag = ($configuration.CreateMinorTag | IsNotNullOrEmpty) ? $configuration.CreateMinorTag -eq 'true' : $env:CreateMinorTag -eq 'true'
$datePrereleaseFormat = ($configuration.DatePrereleaseFormat | IsNotNullOrEmpty) ? $configuration.DatePrereleaseFormat : $env:DatePrereleaseFormat
$incrementalPrerelease = ($configuration.IncrementalPrerelease | IsNotNullOrEmpty) ? $configuration.IncrementalPrerelease -eq 'true' : $env:IncrementalPrerelease -eq 'true'
$versionPrefix = ($configuration.VersionPrefix | IsNotNullOrEmpty) ? $configuration.VersionPrefix : $env:VersionPrefix

Write-Output '-------------------------------------------------'
Write-Output "Auto cleanup enabled:           [$autoCleanup]"
Write-Output "Auto patching enabled:          [$autoPatching]"
Write-Output "Create major tag enabled:       [$createMajorTag]"
Write-Output "Create minor tag enabled:       [$createMinorTag]"
Write-Output "Date-based prerelease format:   [$datePrereleaseFormat]"
Write-Output "Incremental prerelease enabled: [$incrementalPrerelease]"
Write-Output "Version prefix:                 [$versionPrefix]"
Write-Output '-------------------------------------------------'
Write-Output '::endgroup::'


Write-Output '::group::Event information - JSON'
$githubEventJson = Get-Content $env:GITHUB_EVENT_PATH
$githubEventJson | Format-List
Write-Output '::endgroup::'

Write-Output '::group::Event information - Object'
$githubEvent = $githubEventJson | ConvertFrom-Json
$pull_request = $githubEvent.pull_request
$githubEvent | Format-List
Write-Output '::endgroup::'

$isPullRequest = $githubEvent.PSObject.Properties.Name -Contains 'pull_request'
if (-not $isPullRequest) {
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

Write-Output '::group::Pull request - details'
$pull_request | Format-List
Write-Output '::endgroup::'

Write-Output '::group::Pull request - Labels'
$labels = @()
$labels += $pull_request.labels.name
$labels | Format-List
Write-Output '::endgroup::'

$majorTags = @('major', 'breaking')
$minorTags = @('minor', 'feature', 'improvement')
$patchTags = @('patch', 'fix', 'bug')

$createRelease = $pull_request.base.ref -eq 'main' -and ($pull_request.merged).ToString() -eq 'True'
$closedPullRequest = $pull_request.state -eq 'closed' -and ($pull_request.merged).ToString() -eq 'False'
$preRelease = $labels -Contains 'prerelease'
$createPrerelease = $preRelease -and -not $createRelease -and -not $closedPullRequest

$majorRelease = (Compare-Object -ReferenceObject $labels -DifferenceObject $majorTags -IncludeEqual -ExcludeDifferent).Count -gt 0
$minorRelease = (Compare-Object -ReferenceObject $labels -DifferenceObject $minorTags -IncludeEqual -ExcludeDifferent).Count -gt 0 -and -not $majorRelease
$patchRelease = (Compare-Object -ReferenceObject $labels -DifferenceObject $patchTags -IncludeEqual -ExcludeDifferent).Count -gt 0 -and -not $majorRelease -and -not $minorRelease

Write-Output '-------------------------------------------------'
Write-Output "Create a release:               [$createRelease]"
Write-Output "Create a prerelease:            [$createPrerelease]"
Write-Output "Create a major release:         [$majorRelease]"
Write-Output "Create a minor release:         [$minorRelease]"
Write-Output "Create a patch release:         [$patchRelease]"
Write-Output "Closed pull request:            [$closedPullRequest]"
Write-Output '-------------------------------------------------'

if ($createPrerelease -or $createRelease) {
    Write-Output '::group::Get releases'
    $releases = gh release list --json 'createdAt,isDraft,isLatest,isPrerelease,name,publishedAt,tagName' | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Failed to list all releases for the repo.'
        exit $LASTEXITCODE
    }
    $releases | Select-Object -Property name, isPrerelease, isLatest, publishedAt | Format-Table
    Write-Output '::endgroup::'

    Write-Output '::group::Get latest version'
    $latestRelease = $releases | Where-Object { $_.isLatest -eq $true }
    $latestRelease | Format-List
    $latestVersionString = $latestRelease.tagName
    if ($latestVersionString | IsNotNullOrEmpty) {
        $latestVersion = $latestVersionString | ConvertTo-SemVer
        Write-Output '-------------------------------------------------'
        Write-Output 'Latest version:'
        $latestVersion | Format-Table
        $latestVersion = '{0}{1}.{2}.{3}' -f $versionPrefix, $latestVersion.Major, $latestVersion.Minor, $latestVersion.Patch
    }
    Write-Output '::endgroup::'

    Write-Output '-------------------------------------------------'
    Write-Output "Latest version:                 [$latestVersion]"
    Write-Output '-------------------------------------------------'

    Write-Output '::group::Calculate new version'
    $version = $latestVersion | ConvertTo-SemVer
    $major = $version.Major
    $minor = $version.Minor
    $patch = $version.Patch
    if ($majorRelease) {
        Write-Output 'Incrementing major version.'
        $major++
        $minor = 0
        $patch = 0
    } elseif ($minorRelease) {
        Write-Output 'Incrementing minor version.'
        $minor++
        $patch = 0
    } elseif ($patchRelease -or $autoPatching) {
        Write-Output 'Incrementing patch version.'
        $patch++
    } else {
        Write-Output 'Skipping release creation, exiting.'
        return
    }

    $newVersion = '{0}{1}.{2}.{3}' -f $versionPrefix, $major, $minor, $patch
    Write-Output "Partly new version: [$newVersion]"

    if ($createPrerelease) {
        Write-Output "Adding a prerelease tag to the version using the branch name [$preReleaseName]."
        $newVersion = "$newVersion-$preReleaseName"
        Write-Output "Partly new version: [$newVersion]"

        if ($datePrereleaseFormat | IsNotNullOrEmpty) {
            Write-Output "Using date-based prerelease: [$datePrereleaseFormat]."
            $newVersion = $newVersion + '.' + (Get-Date -Format $datePrereleaseFormat)
            Write-Output "Partly new version: [$newVersion]"
        }

        if ($incrementalPrerelease) {
            $prereleases = $releases | Where-Object { $_.tagName -like "$newVersion*" }
            $prereleases | Select-Object -Property @{n = 'number'; e = { [int](($_.tagName -Split '\.')[-1]) } }, name, publishedAt, isPrerelease, isLatest | Format-Table

            if ($prereleases.count -gt 0) {
                $latestPrereleaseVersion = ($prereleases[0].tagName | ConvertTo-SemVer) | Select-Object -ExpandProperty Prerelease
                Write-Output "Latest prerelease:              [$latestPrereleaseVersion]"
                $latestPrereleaseNumber = [int]($latestPrereleaseVersion -Split '\.')[-1]
                Write-Output "Latest prerelease number:       [$latestPrereleaseNumber]"
            }

            $newPrereleaseNumber = 0 + $latestPrereleaseNumber + 1
            $newVersion = $newVersion + '.' + $newPrereleaseNumber
        }
    }
    Write-Output '::endgroup::'
    Write-Output '-------------------------------------------------'
    Write-Output "New version:                    [$newVersion]"
    Write-Output '-------------------------------------------------'

    Write-Output "::group::Create new release [$newVersion]"
    if ($createPrerelease) {
        $releaseExists = $releases.tagName -Contains $newVersion
        if ($releaseExists -and -not $incrementalPrerelease) {
            Write-Output 'Release already exists, recreating.'
            gh release delete $newVersion --cleanup-tag --yes
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to delete the release [$newVersion]."
                exit $LASTEXITCODE
            }
        }

        gh release create $newVersion --title $newVersion --generate-notes --prerelease
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create the release [$newVersion]."
            exit $LASTEXITCODE
        }
    } else {
        gh release create $newVersion --title $newVersion --generate-notes
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create the release [$newVersion]."
            exit $LASTEXITCODE
        }

        if ($createMajorTag) {
            $majorTag = ('{0}{1}' -f $versionPrefix, $major)
            git tag -f $majorTag 'main'
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to create major tag [$majorTag]."
                exit $LASTEXITCODE
            }
        }

        if ($createMinorTag) {
            $minorTag = ('{0}{1}.{2}' -f $versionPrefix, $major, $minor)
            git tag -f $minorTag 'main'
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to create minor tag [$minorTag]."
                exit $LASTEXITCODE
            }
        }

        git push origin --tags --force
        if ($LASTEXITCODE -ne 0) {
            Write-Error 'Failed to push tags.'
            exit $LASTEXITCODE
        }
        Write-Output '::endgroup::'
    }
} else {
    Write-Output 'Skipping release creation.'
}

Write-Output "::notice::Release created: [$newVersion]"

Write-Output '::group::List prereleases using the same name'
$prereleasesToCleanup = $releases | Where-Object { $_.tagName -like "*$preReleaseName*" }
$prereleasesToCleanup | Select-Object -Property name, publishedAt, isPrerelease, isLatest | Format-Table
Write-Output '::endgroup::'

if (($closedPullRequest -or $createRelease) -and $autoCleanup) {
    Write-Output "::group::Cleanup prereleases for [$preReleaseName]"
    foreach ($rel in $prereleasesToCleanup) {
        $relTagName = $rel.tagName
        Write-Output "Deleting prerelease:            [$relTagName]."
        gh release delete $rel.tagName --cleanup-tag --yes
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to delete release [$relTagName]."
            exit $LASTEXITCODE
        }
    }
    Write-Output '::endgroup::'
}
