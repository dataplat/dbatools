<#
.SYNOPSIS
    Fails when the SMO in the pinned dbatools.library raises or drops the version floor of an object type.

.DESCRIPTION
    SMO describes every object type it can enumerate (Server, Database, Login, ...) in an XML resource embedded
    in Microsoft.SqlServer.SqlEnum.dll. The root element of each resource declares the lowest major version SMO
    enumerates that type for (min_major) and the same for Azure SQL Database (cloud_min_major). Below that floor
    SMO refuses the enumeration, whatever dbatools asks for with Connect-DbaInstance -MinimumVersion.

    A new SMO can raise such a floor without any change in dbatools. SQL Server 2005 support was lost that way:
    229 of the 304 resources of SMO 18.100 declare min_major 10. See #10600.

    This script compares the floors of the SqlEnum.dll that is loaded right now with the reviewed baseline in
    .github/smo-resource-floors.json and fails on every floor that changed and every resource that disappeared.
    New resources are listed, but do not fail. It is an early warning about the library, not proof that every
    operation above a declared floor works.

    It first checks that the SqlEnum.dll it reads belongs to the dbatools.library the pin in
    .github/dbatools-library-version.json asks for, so it cannot pass by reading some other SMO.

    Run it after Import-Module ./dbatools.psd1. After a reviewed change, run it with -UpdateBaseline and commit
    the new baseline together with the pin.

.PARAMETER BaselinePath
    The reviewed baseline. Defaults to .github/smo-resource-floors.json.

.PARAMETER VersionConfigPath
    The library pin. Defaults to .github/dbatools-library-version.json.

.PARAMETER UpdateBaseline
    Writes the floors of the loaded SqlEnum.dll to the baseline instead of comparing them.

.EXAMPLE
    PS C:\> Import-Module ./dbatools.psd1; ./.github/scripts/Test-SmoResourceFloor.ps1

    Compares the loaded SMO with the baseline.
#>
[CmdletBinding()]
param(
    [string]$BaselinePath = (Join-Path $PSScriptRoot "../smo-resource-floors.json"),
    [string]$VersionConfigPath = (Join-Path $PSScriptRoot "../dbatools-library-version.json"),
    [switch]$UpdateBaseline
)

$ErrorActionPreference = "Stop"

# The library has to be the pinned one. A preview build reports only the numeric part as its version.
$pinnedVersion = (Get-Content -LiteralPath $VersionConfigPath -Raw | ConvertFrom-Json).version
$pinnedModuleVersion = $pinnedVersion.Split("-")[0]
$library = @(Get-Module -Name dbatools.library)
if ($library.Count -eq 0) {
    throw "dbatools.library is not loaded. Run Import-Module ./dbatools.psd1 first."
}
if ($library.Count -gt 1) {
    throw "More than one dbatools.library is loaded: $($library.ModuleBase -join ", ")"
}
$library = $library[0]
if ("$($library.Version)" -ne $pinnedModuleVersion) {
    throw "The loaded dbatools.library is $($library.Version) from $($library.ModuleBase), but the pin asks for $pinnedVersion."
}

$sqlEnum = @([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $PSItem.GetName().Name -eq "Microsoft.SqlServer.SqlEnum" })
if ($sqlEnum.Count -eq 0) {
    throw "Microsoft.SqlServer.SqlEnum is not loaded, although dbatools.library $($library.Version) is."
}
if ($sqlEnum.Count -gt 1) {
    throw "More than one Microsoft.SqlServer.SqlEnum is loaded: $($sqlEnum.Location -join ", ")"
}
$sqlEnum = $sqlEnum[0]
$libraryBase = [System.IO.Path]::GetFullPath($library.ModuleBase)
$sqlEnumPath = [System.IO.Path]::GetFullPath($sqlEnum.Location)
if (-not $sqlEnumPath.StartsWith($libraryBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Microsoft.SqlServer.SqlEnum was loaded from $sqlEnumPath, not from dbatools.library in $libraryBase."
}
$sqlEnumFileVersion = (Get-Item -LiteralPath $sqlEnumPath).VersionInfo.FileVersion
Write-Host "Reading Microsoft.SqlServer.SqlEnum $sqlEnumFileVersion from dbatools.library $pinnedVersion"

# The floors of the loaded SMO, one entry per XML resource, in ordinal order so the baseline is stable.
[string[]]$resourceNames = $sqlEnum.GetManifestResourceNames() | Where-Object { $PSItem -like "*.xml" }
[System.Array]::Sort($resourceNames, [System.StringComparer]::Ordinal)
$currentFloor = New-Object System.Collections.Specialized.OrderedDictionary
foreach ($resourceName in $resourceNames) {
    $reader = New-Object System.IO.StreamReader ($sqlEnum.GetManifestResourceStream($resourceName))
    try {
        $resourceXml = [xml]$reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
    $currentFloor[$resourceName] = [ordered]@{
        min_major       = $resourceXml.DocumentElement.GetAttribute("min_major")
        cloud_min_major = $resourceXml.DocumentElement.GetAttribute("cloud_min_major")
    }
}
if ($currentFloor.Count -eq 0) {
    throw "Microsoft.SqlServer.SqlEnum $sqlEnumFileVersion has no XML resources, so there is nothing to compare."
}

if ($UpdateBaseline) {
    $baseline = [ordered]@{
        notes              = "Reviewed SMO enumeration floors, see .github/scripts/Test-SmoResourceFloor.ps1 and #10600"
        library            = $pinnedVersion
        sqlEnumFileVersion = $sqlEnumFileVersion
        resources          = $currentFloor
    }
    $baseline | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $BaselinePath -Encoding utf8
    Write-Host "Wrote the floors of $($currentFloor.Count) resources to $BaselinePath"
    return
}

$baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
$baselineNames = @($baseline.resources.PSObject.Properties.Name)

$floorProblem = foreach ($resourceName in $baselineNames) {
    $expected = $baseline.resources.$resourceName
    if (-not $currentFloor.Contains($resourceName)) {
        [PSCustomObject]@{
            Resource = $resourceName
            Problem  = "resource disappeared"
            Baseline = "min_major [$($expected.min_major)], cloud_min_major [$($expected.cloud_min_major)]"
            Current  = ""
        }
        continue
    }
    $actual = $currentFloor[$resourceName]
    foreach ($attributeName in "min_major", "cloud_min_major") {
        if ($actual[$attributeName] -ne $expected.$attributeName) {
            [PSCustomObject]@{
                Resource = $resourceName
                Problem  = "$attributeName changed"
                Baseline = "[$($expected.$attributeName)]"
                Current  = "[$($actual[$attributeName])]"
            }
        }
    }
}

$newResource = @($currentFloor.Keys | Where-Object { $PSItem -notin $baselineNames })
if ($newResource) {
    Write-Host "New resources, not in the baseline yet: $($newResource -join ", ")"
}

if ($floorProblem) {
    $floorProblem | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
    $failureMessage = @"
SMO $sqlEnumFileVersion in dbatools.library $pinnedVersion changed $(@($floorProblem).Count) enumeration floor(s) compared with $($baseline.sqlEnumFileVersion) in the baseline.
A raised min_major means SMO no longer enumerates that object type on older SQL Server versions, whatever
Connect-DbaInstance -MinimumVersion allows. Check the commands that use these types, then run
./.github/scripts/Test-SmoResourceFloor.ps1 -UpdateBaseline and commit the new baseline with the pin.
"@
    throw $failureMessage
}

Write-Host "All $($baselineNames.Count) SMO enumeration floors match the baseline."
