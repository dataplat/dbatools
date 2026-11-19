param(
    [string]$ModuleVersion,
    [string]$MainVersion,
    [string]$CsvVersion
)

$ErrorActionPreference = 'Stop'

$scriptroot = $PSScriptRoot
if (-not $scriptroot) {
    $scriptroot = Split-Path -Path $MyInvocation.MyCommand.Path
}

$root = Split-Path -Path $scriptroot
$manifestPath = Join-Path $root "dbatools.library.psd1"
$mainProjectPath = Join-Path $root "project\dbatools\dbatools.csproj"
$csvProjectPath = Join-Path $root "project\Dataplat.Dbatools.Csv\Dataplat.Dbatools.Csv.csproj"

function Test-Utf8Bom {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -Path $Path).Path)
    return $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
}

function Set-TextContent {
    param(
        [string]$Path,
        [string]$Value
    )

    $resolvedPath = (Resolve-Path -Path $Path).Path
    $hasUtf8Bom = Test-Utf8Bom -Path $Path
    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $hasUtf8Bom
    [System.IO.File]::WriteAllText($resolvedPath, $Value, $encoding)
}

function Get-XmlElementValue {
    param(
        [string]$Path,
        [string]$ElementName
    )

    [xml]$document = Get-Content -Path $Path -Raw
    $propertyGroup = $document.Project.PropertyGroup | Where-Object { $_.$ElementName } | Select-Object -First 1

    if (-not $propertyGroup) {
        throw "Could not find <$ElementName> in $Path"
    }

    return [string]$propertyGroup.$ElementName
}

function Set-XmlElementValue {
    param(
        [string]$Path,
        [string]$ElementName,
        [string]$OldValue,
        [string]$NewValue
    )

    $content = Get-Content -Path $Path -Raw
    $oldElement = "<$ElementName>$OldValue</$ElementName>"
    $newElement = "<$ElementName>$NewValue</$ElementName>"

    if (-not $content.Contains($oldElement)) {
        throw "Could not find expected element $oldElement in $Path"
    }

    $content = $content.Replace($oldElement, $newElement)
    Set-TextContent -Path $Path -Value $content
}

function Get-ModuleVersion {
    param([string]$Path)

    $content = Get-Content -Path $Path -Raw
    $match = [regex]::Match($content, "ModuleVersion\s*=\s*'([^']+)'")

    if (-not $match.Success) {
        throw "Could not find ModuleVersion in $Path"
    }

    return $match.Groups[1].Value
}

function Set-ModuleVersion {
    param(
        [string]$Path,
        [string]$Version
    )

    $content = Get-Content -Path $Path -Raw
    $pattern = [regex]"(ModuleVersion\s*=\s*')([^']+)(')"

    if (-not $pattern.IsMatch($content)) {
        throw "Could not update ModuleVersion in $Path"
    }

    $updated = $pattern.Replace($content, { param($match) $match.Groups[1].Value + $Version + $match.Groups[3].Value }, 1)
    Set-TextContent -Path $Path -Value $updated
}

function Add-OneToLastVersionPart {
    param(
        [string]$Version,
        [int]$MinimumParts
    )

    $label = ""
    $core = $Version
    $dashIndex = $Version.IndexOf("-")

    if ($dashIndex -ge 0) {
        $core = $Version.Substring(0, $dashIndex)
        $label = $Version.Substring($dashIndex)
    }

    $parts = @($core.Split("."))
    while ($parts.Count -lt $MinimumParts) {
        $parts += "0"
    }

    $lastIndex = $parts.Count - 1
    $number = 0
    if (-not [int]::TryParse($parts[$lastIndex], [ref]$number)) {
        throw "Cannot bump version '$Version' because '$($parts[$lastIndex])' is not numeric."
    }

    $parts[$lastIndex] = [string]($number + 1)
    return ($parts -join ".") + $label
}

function Assert-Version {
    param(
        [string]$Name,
        [string]$Version,
        [string]$Pattern
    )

    if ($Version -notmatch $Pattern) {
        throw "$Name '$Version' does not match expected version format."
    }
}

$oldModuleVersion = Get-ModuleVersion -Path $manifestPath
$oldMainAssemblyVersion = Get-XmlElementValue -Path $mainProjectPath -ElementName "AssemblyVersion"
$oldMainFileVersion = Get-XmlElementValue -Path $mainProjectPath -ElementName "FileVersion"
$oldMainVersion = Get-XmlElementValue -Path $mainProjectPath -ElementName "Version"
$oldCsvVersion = Get-XmlElementValue -Path $csvProjectPath -ElementName "Version"

if (-not $ModuleVersion) {
    $ModuleVersion = Get-Date -Format "yyyy.M.d"
}
if (-not $MainVersion) {
    $MainVersion = Add-OneToLastVersionPart -Version $oldMainAssemblyVersion -MinimumParts 4
}
if (-not $CsvVersion) {
    $CsvVersion = Add-OneToLastVersionPart -Version $oldCsvVersion -MinimumParts 3
}

Assert-Version -Name "ModuleVersion" -Version $ModuleVersion -Pattern "^\d{4}\.\d{1,2}\.\d{1,2}$"
Assert-Version -Name "MainVersion" -Version $MainVersion -Pattern "^\d+\.\d+\.\d+\.\d+$"
Assert-Version -Name "CsvVersion" -Version $CsvVersion -Pattern "^\d+\.\d+\.\d+(-[0-9A-Za-z][0-9A-Za-z\.-]*)?$"

if ($oldMainAssemblyVersion -ne $oldMainFileVersion) {
    throw "AssemblyVersion ($oldMainAssemblyVersion) and FileVersion ($oldMainFileVersion) do not match."
}
if ($oldMainAssemblyVersion -ne $oldMainVersion) {
    throw "AssemblyVersion ($oldMainAssemblyVersion) and Version ($oldMainVersion) do not match."
}

Set-ModuleVersion -Path $manifestPath -Version $ModuleVersion
Set-XmlElementValue -Path $mainProjectPath -ElementName "AssemblyVersion" -OldValue $oldMainAssemblyVersion -NewValue $MainVersion
Set-XmlElementValue -Path $mainProjectPath -ElementName "FileVersion" -OldValue $oldMainFileVersion -NewValue $MainVersion
Set-XmlElementValue -Path $mainProjectPath -ElementName "Version" -OldValue $oldMainVersion -NewValue $MainVersion
Set-XmlElementValue -Path $csvProjectPath -ElementName "Version" -OldValue $oldCsvVersion -NewValue $CsvVersion

Write-Host "Bumped versions:" -ForegroundColor Green
Write-Host "  ModuleVersion: $oldModuleVersion -> $ModuleVersion"
Write-Host "  dbatools AssemblyVersion/FileVersion/Version: $oldMainAssemblyVersion -> $MainVersion"
Write-Host "  Dataplat.Dbatools.Csv Version: $oldCsvVersion -> $CsvVersion"
