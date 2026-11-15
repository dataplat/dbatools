---
name: update-buildref
description: Bring bin/dbatools-buildref-index.json up to date with the SQL Server builds Microsoft published - cumulative updates (CU) and security updates (GDR) - verify it and open the pull request. Use when Microsoft ships a new CU or a Patch Tuesday security update, when Get-DbaBuild or Test-DbaBuild does not know a build or calls it "Approximate", or when someone asks to "update the buildref", "add the new CU", "add the security updates of <month>".
argument-hint: "[optional: the SQL Server versions to check, e.g. 2022 2025]"
---

# Update the SQL Server Build Reference

`bin/dbatools-buildref-index.json` is the list of every SQL Server build that `Get-DbaBuild`, `Test-DbaBuild` and `Update-DbaBuildReference` know. When Microsoft ships a build that is not in it, `Get-DbaBuild` reports an approximate match and `Test-DbaBuild -Latest` measures every instance against an outdated target - it calls an instance compliant although a newer security update exists.

`.github/scripts/Sync-BuildReferenceIndex.ps1` does the mechanical part: it reads the build version pages of Microsoft, reports what the index lacks and, with `-Apply`, inserts it. **Do not type new entries by hand.** The script writes them in the exact shape the maintainers write them, and it was checked to reproduce the hand-made updates #10786 and #10808 byte for byte. What is left for you is the judgement: whether to open a PR at all, what the script cannot know, and the review.

## 1. Make sure nobody is already on it

Several maintainers add new builds within a day or two of a release. Look for an open pull request that changes the index before doing anything:

```powershell
$open = gh pr list --repo dataplat/dbatools --state open --limit 200 --json number,title,author,files | ConvertFrom-Json
$open | Where-Object { $PSItem.files.path -contains "bin/dbatools-buildref-index.json" } | ForEach-Object { "#$($PSItem.number) $($PSItem.title) ($($PSItem.author.login))" }
```

If one exists, stop and report it, unless it lacks builds that the script reports as missing - then say so on that pull request instead of opening a second one.

## 2. Branch from development

```
git fetch origin development
git checkout -b buildref-<month>-<year> origin/development
```

## 3. Report

The script needs PowerShell 7 (`pwsh`). learn.microsoft.com blocks most web requests of Windows PowerShell 5.1.

```powershell
./.github/scripts/Sync-BuildReferenceIndex.ps1 | Format-Table -AutoSize
```

Pass `-MajorVersion 2022, 2025` to check only some versions. Without it the script reads the pages of SQL Server 2017, 2019, 2022 and 2025.

- **No output** - the index is current. Stop and say so; there is nothing to commit.
- **Missing** - a build on the page of Microsoft that the index lacks. These are what `-Apply` adds.
- **Differs** - a build in both whose KB number, CU name or release date disagrees with Microsoft. The script never changes these. Check the row on the page; when Microsoft is right, fix the entry by hand in the same pull request, so that the next run starts clean. Example: Microsoft lists 14.0.3015.40 both as CU3 (KB4052987) and as "CU3 + GDR" (KB4058562), so that entry carries both numbers as a `KBList` array.

Show the report to the user before applying it.

## 4. Apply and look at the diff

```powershell
./.github/scripts/Sync-BuildReferenceIndex.ps1 -Apply
git diff --stat
git diff bin/dbatools-buildref-index.json
./.github/scripts/Sync-BuildReferenceIndex.ps1    # must report nothing now, except Differs you decided to leave
```

The diff must show only new entries and the moved `LastUpdated`. Each entry looks like this - a CU gets a `CU` property, a security update does not:

```json
        {
            "CU": "CU10",
            "Version": "17.0.5035",
            "KBList": "5125471",
            "ReleaseDate": "2026-10-22"
        },
        {
            "Version": "17.0.5045",
            "KBList": "5129299",
            "ReleaseDate": "2026-11-10"
        }
```

`LastUpdated` moves to the newest release date added, as the hand-made updates do. It must not be in the future, and `Get-DbaBuild.Tests.ps1` fails for everybody once it is older than 45 days.

## 5. What the script does not do

Handle these by hand and mention them in the pull request:

- **A retired update.** When Microsoft pulls an update, it disappears from the page. The script compares only the builds that are on the page, so it never notices. Add `"Retired": true` to that entry; see 16.0.4235 or 10.50.2874 in the index. `Get-DbaBuild` then warns that the build was retired.
- **A new major version.** The first entry of a new version carries `Name` (the year), and its RTM entry carries `SP` and `SupportedUntil`. Copy the shape of the 17.0 entries. Then add the year to the default of `-MajorVersion` in the script.
- **SQL Server 2016 and older.** Their pages moved to support.microsoft.com in another format, and 2016 left extended support in July 2026. The script does not read them.
- **A changed page layout.** The script throws when a page has no table with a build, KB and release date column. Fix the parser in `Get-MicrosoftBuild` of the script and say so in the pull request; do not fall back to typing entries.

## 6. Verify

Import the module from the repository and look up the new builds. Each must be an `Exact` match with the right CU and KB:

```powershell
Import-Module ./dbatools.psd1 -Force
Get-DbaBuild -Build "<new build>", "<new build>" | Format-Table Build, NameLevel, CULevel, KBLevel, MatchType, ReleaseDate
Test-DbaBuild -Build "<build before the update>" -Latest | Format-Table Build, Compliant, BuildTarget
```

`Get-DbaBuild` copies the repository index over the cached copy in `Path.DbatoolsData` when its `LastUpdated` is newer, so these lookups see the new entries.

The unit tests of `Get-DbaBuild`, `Test-DbaBuild` and `Update-DbaBuildReference` check the whole file: that it parses, that the versions are sorted, the shape of every property, and that `LastUpdated` is recent. They need no SQL Server instance. Run them with the test setup you use for dbatools, if you have one. CI runs them on the pull request either way: the changed files belong to no command, so CI picks the tests from the `(do Build)` marker of the commit message (step 7).

When the script itself changed, also run the repository-wide checks, which cover every PowerShell file including `.github/scripts`:

```powershell
Invoke-Pester -Path ./tests/dbatools.Tests.ps1 -TagFilter Compliance
```

## 7. Commit

Name the release the way Microsoft does, and keep the `(do Build)` marker. CI then runs the test files whose name contains "Build": the three above plus `New-DbaConnectionStringBuilder`:

```
Security updates for SQL 2025, 2022, 2019, 2017 - November 10, 2026

Adds the builds of the security updates of November 10, 2026 to the build
reference index with Sync-BuildReferenceIndex.ps1.

(do Build)
```

For a cumulative update: `SQL Server 2025 CU11`.

## 8. Pull request

```
gh pr create --base development --title "Security updates for SQL 2025, 2022, 2019, 2017 - November 10, 2026" --body "..."
```

- **No `(do ...)` in the title**, see the root `CLAUDE.md`.
- Body: a table of the added builds (version, build, KB, release date), the pages of Microsoft as the source, every hand-made change from step 5 or a Differs row with its reason, and the test result.
- Never merge it; a maintainer merges.

## After the merge

The website copies `bin/dbatools-buildref-index.json` from `development` every day at 09:00 UTC (workflow `updateassets.yml` in dataplat/dataplat.github.io). From then on users get the new builds with `Update-DbaBuildReference` or `Get-DbaBuild -Update`, without waiting for a dbatools release. No second pull request is needed.
