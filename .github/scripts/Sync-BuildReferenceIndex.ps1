<#
.SYNOPSIS
    Compares bin/dbatools-buildref-index.json with the build version pages of Microsoft and adds the builds that are missing.

.DESCRIPTION
    Get-DbaBuild, Test-DbaBuild and Update-DbaBuildReference read the build reference index in
    bin/dbatools-buildref-index.json. Microsoft lists every cumulative update (CU) and every security update (GDR)
    of the supported versions on one page per version:

        https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-<year>/build-versions

    This script reads those pages and compares every build on them with the index. Without -Apply it only reports:

        Missing  The build is on the page of Microsoft, but not in the index.
        Differs  The build is in both, but a KB number of the page is not in the index, or the CU name or the
                 release date disagree. The script never changes these. Check them on the page and fix the entry
                 by hand, so that the next run reports only what is new.

    Microsoft can list one build in two rows, for example as CU3 and as "CU3 + GDR" of SQL Server 2017. Such rows
    are compared as one build that has every KB number of them, and its CU name and release date of the CU row.

    With -Apply it inserts the missing builds at their sorted position and moves LastUpdated to the newest release
    date it added. It edits the file as text, so the existing entries keep their exact formatting and the diff shows
    only the new entries, the same way a hand-made update does. A CU gets the properties CU, Version, KBList and
    ReleaseDate, a security update gets Version, KBList and ReleaseDate.

    The pages of SQL Server 2016 and older moved to support.microsoft.com in a different format and get no new builds
    since 2016 left extended support in July 2026, so they are not read.

    The script throws when a page no longer has the expected tables, so a changed layout cannot pass as "nothing is
    missing".

    It needs PowerShell 7. learn.microsoft.com answers the web requests of Windows PowerShell 5.1 with
    "403 Forbidden" or "The request is blocked." most of the time, while it serves PowerShell 7 reliably.

.PARAMETER MajorVersion
    The SQL Server versions to compare, as the year in the name of the version. Defaults to every version that
    learn.microsoft.com has a build version page for.

.PARAMETER Path
    The build reference index. Defaults to bin/dbatools-buildref-index.json of this repository.

.PARAMETER Apply
    Writes the missing builds to the index. Without it the script only reports.

.EXAMPLE
    PS C:\> ./.github/scripts/Sync-BuildReferenceIndex.ps1

    Reports the builds Microsoft lists that the index does not have, and the entries that disagree with Microsoft.

.EXAMPLE
    PS C:\> ./.github/scripts/Sync-BuildReferenceIndex.ps1 -Apply

    Adds the missing builds to bin/dbatools-buildref-index.json and moves LastUpdated.

.EXAMPLE
    PS C:\> ./.github/scripts/Sync-BuildReferenceIndex.ps1 -MajorVersion 2022 | Where-Object Status -eq Missing

    Lists only the SQL Server 2022 builds that the index does not have.

.NOTES
    Author: the dbatools team + Claude
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidatePattern("^\d{4}$")]
    [string[]]$MajorVersion = @(
        "2017",
        "2019",
        "2022",
        "2025"
    ),
    [string]$Path = (Join-Path -Path $PSScriptRoot -ChildPath "../../bin/dbatools-buildref-index.json"),
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

function ConvertTo-PlainText {
    param([string]$Html)
    $text = [regex]::Replace($Html, "<[^>]+>", " ")
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    [regex]::Replace($text, "\s+", " ").Trim()
}

function ConvertTo-IndexDate {
    # ConvertFrom-Json of PowerShell 7 turns date strings with a time into DateTime.
    param($Value)
    if ($null -eq $Value -or "$Value" -eq "") {
        return ""
    }
    if ($Value -is [datetime]) {
        return $Value.ToString("yyyy-MM-dd")
    }
    "$Value"
}

function Get-MicrosoftBuild {
    param([string]$Year)

    $uri = "https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-$Year/build-versions"
    Write-Verbose -Message "Reading $uri"
    $content = (Invoke-WebRequest -Uri $uri -UseBasicParsing).Content
    $culture = [System.Globalization.CultureInfo]::InvariantCulture

    $builds = @(foreach ($table in [regex]::Matches($content, "(?s)<table[^>]*>.*?</table>")) {
            $headers = @([regex]::Matches($table.Value, "(?s)<th[^>]*>(.*?)</th>") | ForEach-Object { ConvertTo-PlainText -Html $PSItem.Groups[1].Value })
            $buildColumn = [array]::FindIndex($headers, [Predicate[string]] { param($header) $header -match "^SQL Server (build|product) version$" })
            $kbColumn = [array]::FindIndex($headers, [Predicate[string]] { param($header) $header -match "^Knowledge Base number$" })
            $dateColumn = [array]::FindIndex($headers, [Predicate[string]] { param($header) $header -match "^Release date$" })
            if ($buildColumn -lt 0 -or $kbColumn -lt 0 -or $dateColumn -lt 0) {
                Write-Verbose -Message "Skipping a table on the $Year page with the columns: $($headers -join " | ")"
                continue
            }
            foreach ($row in [regex]::Matches($table.Value, "(?s)<tr[^>]*>(.*?)</tr>")) {
                $cells = @([regex]::Matches($row.Groups[1].Value, "(?s)<td[^>]*>(.*?)</td>") | ForEach-Object { ConvertTo-PlainText -Html $PSItem.Groups[1].Value })
                if ($cells.Count -eq 0) {
                    continue
                }
                $name = $cells[0]
                $buildMatch = [regex]::Match($cells[$buildColumn], "^(\d+)\.(\d+)\.(\d+)")
                if (-not $buildMatch.Success) {
                    Write-Warning -Message "SQL Server $Year, row `"$name`": cannot read the build `"$($cells[$buildColumn])`", skipping it."
                    continue
                }
                $kbMatch = [regex]::Match($cells[$kbColumn], "KB\s*(\d+)")
                $kb = ""
                if ($kbMatch.Success) {
                    $kb = $kbMatch.Groups[1].Value
                }
                $releaseDate = ""
                $parsedDate = [datetime]::MinValue
                if ([datetime]::TryParseExact($cells[$dateColumn], "MMMM d, yyyy", $culture, [System.Globalization.DateTimeStyles]::None, [ref]$parsedDate)) {
                    $releaseDate = $parsedDate.ToString("yyyy-MM-dd")
                } else {
                    # Test-DbaBuild -MaxTimeBehind cannot judge a build without a release date.
                    Write-Warning -Message "SQL Server $Year, build $($cells[$buildColumn]): cannot read the release date `"$($cells[$dateColumn])`", the entry gets none."
                }
                # Only a cumulative update itself carries a CU name. "CU10 + GDR" is a security update on top of CU10.
                $cu = ""
                $cuMatch = [regex]::Match($name, "^CU(\d+)\b")
                if ($cuMatch.Success -and $name -notmatch "GDR") {
                    $cu = "CU$($cuMatch.Groups[1].Value)"
                }
                [PSCustomObject]@{
                    MajorVersion = $Year
                    Name         = $name
                    Version      ="$($buildMatch.Groups[1].Value).$($buildMatch.Groups[2].Value).$($buildMatch.Groups[3].Value)"
                    CU           = $cu
                    KB           = $kb
                    ReleaseDate  = $releaseDate
                }
            }
        })

    if ($builds.Count -eq 0) {
        throw "Found no builds on $uri. The layout of the page probably changed, so this script needs an update."
    }
    $majors = @($builds | ForEach-Object { $PSItem.Version.Split(".")[0] } | Select-Object -Unique)
    if ($majors.Count -ne 1) {
        throw "The builds on $uri belong to more than one major version ($($majors -join ", ")). The layout of the page probably changed."
    }
    $builds
}

function New-EntryLines {
    param($Build)
    $properties = @()
    if ($Build.CU) {
        $properties += "            `"CU`": `"$($Build.CU)`""
    }
    $properties += "            `"Version`": `"$($Build.Version)`""
    $kbs = @($Build.KB)
    if ($kbs.Count -eq 1) {
        $properties += "            `"KBList`": `"$($kbs[0])`""
    } elseif ($kbs.Count -gt 1) {
        $kbLines = @($kbs | ForEach-Object { "                `"$PSItem`"" }) -join ",$newline"
        $properties += "            `"KBList`": [$newline$kbLines$newline            ]"
    }
    if ($Build.ReleaseDate) {
        $properties += "            `"ReleaseDate`": `"$($Build.ReleaseDate)`""
    }
    "        {"
    for ($i = 0; $i -lt $properties.Count; $i++) {
        if ($i -lt $properties.Count - 1) {
            "$($properties[$i]),"
        } else {
            $properties[$i]
        }
    }
    "        }"
}

# Read the index as text and as data. The text is what gets written back, the data is what gets compared.
$resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath
$text = [System.IO.File]::ReadAllText($resolvedPath)
$newline = "`n"
if ($text.Contains("`r`n")) {
    $newline = "`r`n"
}
$lines = $text -split "\r?\n"
$index = $text | ConvertFrom-Json

$dataStart = -1
$dataEnd = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($dataStart -lt 0 -and $lines[$i] -match "^    `"Data`": \[\s*`$") {
        $dataStart = $i
    } elseif ($dataStart -ge 0 -and $lines[$i] -match "^    \]\s*`$") {
        $dataEnd = $i
        break
    }
}
if ($dataStart -lt 0 -or $dataEnd -lt 0) {
    throw "Cannot find the Data array in $resolvedPath. Its formatting is not the one this script expects."
}

# Every entry is a block from "        {" to "        }" or "        },". The closing line is stored without the comma.
$blockStart = -1
$blocks = @(for ($i = $dataStart + 1; $i -lt $dataEnd; $i++) {
        if ($lines[$i] -match "^        \{\s*`$") {
            $blockStart = $i
        } elseif ($lines[$i] -match "^        \},?\s*`$") {
            if ($blockStart -lt 0) {
                throw "Line $($i + 1) of $resolvedPath closes an entry that was never opened."
            }
            [PSCustomObject]@{
                Lines = @($lines[$blockStart .. ($i - 1)]) + "        }"
                Key   = $null
            }
            $blockStart = -1
        }
    })
if ($blocks.Count -ne @($index.Data).Count) {
    throw "Found $($blocks.Count) entry blocks in the text of $resolvedPath, but $(@($index.Data).Count) entries in its data. Its formatting is not the one this script expects."
}

# The data and the text blocks are in the same order. Key both by the first three parts of the version.
$indexByVersion = @{ }
for ($i = 0; $i -lt $blocks.Count; $i++) {
    $entry = $index.Data[$i]
    $blocks[$i].Key = [version]((($entry.Version -split "\.")[0 .. 2]) -join ".")
    if ($i -gt 0 -and $blocks[$i].Key -lt $blocks[$i - 1].Key) {
        throw "The index is not sorted: $($entry.Version) comes after $($index.Data[$i - 1].Version). Fix that first, the tests of Get-DbaBuild require the order."
    }
    $indexByVersion["$($blocks[$i].Key)"] = $entry
}

$missing = @()
foreach ($year in $MajorVersion) {
    # Microsoft can list one build twice, for example CU3 and "CU3 + GDR" of SQL Server 2017 are both 14.0.3015.40.
    # Such rows become one entry with every KB of them. Its CU name and release date come from the CU row.
    foreach ($group in (Get-MicrosoftBuild -Year $year | Group-Object -Property Version)) {
        $primary = @(@($group.Group | Where-Object CU) + @($group.Group | Where-Object { -not $PSItem.CU }))[0]
        $build = [PSCustomObject]@{
            MajorVersion = $year
            Name         = @($group.Group.Name) -join " / "
            Version      = $group.Name
            CU           = $primary.CU
            KB           = @($group.Group.KB | Where-Object { $PSItem } | Select-Object -Unique)
            ReleaseDate  = $primary.ReleaseDate
        }
        $entry = $indexByVersion[$build.Version]
        if (-not $entry) {
            $missing += $build
            [PSCustomObject]@{
                Status       = "Missing"
                MajorVersion = $build.MajorVersion
                Name         = $build.Name
                Version      = $build.Version
                CU           = $build.CU
                KB           = $build.KB -join ", "
                ReleaseDate  = $build.ReleaseDate
                Detail       = ""
            }
            continue
        }

        $details = @()
        $indexKbs = @($entry.KBList | Where-Object { $PSItem } | ForEach-Object { "$PSItem" })
        $missingKbs = @($build.KB | Where-Object { $PSItem -notin $indexKbs })
        if ($missingKbs.Count -gt 0) {
            $details += "KB $($missingKbs -join ", ") not in the index, which has $($indexKbs -join ", ")"
        }
        if ($build.CU -and $build.CU -ne $entry.CU) {
            $details += "CU is `"$($entry.CU)`" in the index"
        }
        $indexDate = ConvertTo-IndexDate -Value $entry.ReleaseDate
        if ($build.ReleaseDate -and $build.ReleaseDate -ne $indexDate) {
            if ($indexDate) {
                $details += "ReleaseDate is $indexDate in the index"
            } else {
                $details += "ReleaseDate is missing in the index"
            }
        }
        if ($details.Count -gt 0) {
            [PSCustomObject]@{
                Status       = "Differs"
                MajorVersion = $build.MajorVersion
                Name         = $build.Name
                Version      = $build.Version
                CU           = $build.CU
                KB           = $build.KB -join ", "
                ReleaseDate  = $build.ReleaseDate
                Detail       = $details -join "; "
            }
        }
    }
}

if (-not $Apply) {
    return
}
if ($missing.Count -eq 0) {
    Write-Host "Nothing to add, the index has every build Microsoft lists for SQL Server $($MajorVersion -join ", ")."
    return
}

$missing = @($missing | Sort-Object -Property { [version]$PSItem.Version })

# Both lists are sorted, so a merge puts every new entry in front of the first existing entry with a higher version.
$next = 0
$merged = @(foreach ($block in $blocks) {
        while ($next -lt $missing.Count -and [version]$missing[$next].Version -lt $block.Key) {
            [PSCustomObject]@{ Lines = @(New-EntryLines -Build $missing[$next]) }
            $next++
        }
        $block
    }
    while ($next -lt $missing.Count) {
        [PSCustomObject]@{ Lines = @(New-EntryLines -Build $missing[$next]) }
        $next++
    })

$dataLines = @(for ($i = 0; $i -lt $merged.Count; $i++) {
        $blockLines = @($merged[$i].Lines)
        if ($i -lt $merged.Count - 1) {
            $blockLines[-1] = "$($blockLines[-1]),"
        }
        $blockLines
    })

# LastUpdated moves to the newest release date added, the same way the hand-made updates set it.
$newestRelease = ($missing | Where-Object ReleaseDate | Sort-Object -Property ReleaseDate | Select-Object -Last 1).ReleaseDate
$lastUpdated = Get-Date -Date $index.LastUpdated
if ($newestRelease -and [datetime]$newestRelease -gt $lastUpdated) {
    $lastUpdated = [datetime]$newestRelease
}
$lastUpdatedPattern = "^(    `"LastUpdated`": `")[^`"]*(`",?)`$"
$lastUpdatedValue = "`${1}$($lastUpdated.ToString("yyyy-MM-ddT00:00:00"))`${2}"
$headLines = @($lines[0 .. $dataStart] | ForEach-Object { $PSItem -replace $lastUpdatedPattern, $lastUpdatedValue })
$tailLines = @($lines[$dataEnd .. ($lines.Count - 1)])
$newText = ($headLines + $dataLines + $tailLines) -join $newline

# Check the result before it replaces the file.
$newIndex = $newText | ConvertFrom-Json
if (@($newIndex.Data).Count -ne @($index.Data).Count + $missing.Count) {
    throw "The new index has $(@($newIndex.Data).Count) entries, expected $(@($index.Data).Count + $missing.Count). Nothing was written."
}

$utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
[System.IO.File]::WriteAllText($resolvedPath, $newText, $utf8NoBom)
Write-Host "Added $($missing.Count) builds to $resolvedPath, LastUpdated is now $($lastUpdated.ToString("yyyy-MM-dd"))."
