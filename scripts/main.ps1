Write-Output '::group::Utilities'
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

Write-Output '::group::Environment variables'
Get-ChildItem -Path Env: | Select-Object Name, Value | Sort-Object Name | Format-Table -AutoSize
Write-Output '::endgroup::'

$autoPatching = $env:AutoPatching -eq 'true'
$incrementalPrerelease = $env:IncrementalPrerelease -eq 'true'
$versionPrefix = $env:VersionPrefix
Write-Output '-------------------------------------------------'
Write-Output "Auto patching enabled:          [$autoPatching]"
Write-Output "Incremental prerelease enabled: [$autoPatching]"
Write-Output "Version prefix:                 [$versionPrefix]"
Write-Output '-------------------------------------------------'

$githubEventJson = Get-Content $env:GITHUB_EVENT_PATH
$githubEvent = $githubEventJson | ConvertFrom-Json
$pull_request = $githubEvent.pull_request

Write-Output '::group::Event information - JSON'
$githubEventJson | Format-List
Write-Output '::endgroup::'

Write-Output '::group::Event information - Object'
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
$majorRelease = $labels -Contains 'major' -or $labels -Contains 'breaking'
$minorRelease = $labels -Contains 'minor' -or $labels -Contains 'feature' -or $labels -Contains 'improvement'
$patchRelease = $labels -Contains 'patch' -or $labels -Contains 'fix' -or $labels -Contains 'bug'
$preRelease = $labels -Contains 'prerelease'
Write-Output '::endgroup::'

Write-Output '-------------------------------------------------'
Write-Output "Is a major release:             [$majorRelease]"
Write-Output "Is a minor release:             [$minorRelease]"
Write-Output "Is a patch release:             [$patchRelease]"
Write-Output "Is a prerelease:                [$preRelease]"
Write-Output '-------------------------------------------------'

$mergedToMain = $pull_request.base.ref -eq 'main' -and $pull_request.merged -eq 'True'

# Skip out if not a merge to main or a prerelease
if (-not ($preRelease -or $mergedToMain)) {
    Write-Output 'Skipping release creation, exiting.'
    return
}
if ($mergedToMain) {
    $preRelease = $false
}

Write-Output '::group::Get releases'
$releases = gh release list --json 'createdAt,isDraft,isLatest,isPrerelease,name,publishedAt,tagName' | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to list all releases for the repo."
    exit $LASTEXITCODE
}
$releases | Format-List
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

if ($preRelease) {
    Write-Output "Adding a prerelease tag to the version using the branch name [$preReleaseName]."
    $newVersion = "$newVersion-$preReleaseName"
    Write-Output "Partly new version: [$newVersion]"

    if ($incrementalPrerelease) {
        $prereleases = $releases | Where-Object { $_.tagName -like "$newVersion*" } | Sort-Object -Descending -Property tagName
        Write-Output "Prereleases:                    [$($prereleases.count)]"
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
if ($preRelease) {
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
    return
}

gh release create $newVersion --title $newVersion --generate-notes
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create the release [$newVersion]."
    exit $LASTEXITCODE
}

$majorTag = ('{0}{1}' -f $versionPrefix, $major)
git tag -f $majorTag 'main'
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create major tag [$majorTag]."
    exit $LASTEXITCODE
}

$minorTag = ('{0}{1}.{2}' -f $versionPrefix, $major, $minor)
git tag -f $minorTag 'main'
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create minor tag [$minorTag]."
    exit $LASTEXITCODE
}

git push origin --tags --force
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to push tags."
    exit $LASTEXITCODE
}
Write-Output '::endgroup::'

Write-Output "::group::Cleanup prereleases for [$preReleaseName]"
$prereleasesToCleanup = $releases | Where-Object { $_.tagName -like "*$preReleaseName*" }
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
