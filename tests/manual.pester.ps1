<#
    .SYNOPSIS
        Runs dbatools tests.

    .DESCRIPTION
        This is an helper to automate running tests locally

    .PARAMETER Path
        The Path to the test files to run. It accepts multiple test file paths passed in (e.g. .\Find-DbaOrphanedFile.Tests.ps1) as well
        as simple strings (e.g. "orphaned" will run all files matching .\*orphaned*.Tests.ps1)

    .PARAMETER Show
        Gets passed down to Pester's -Show parameter (useful if you want to reduce verbosity)

    .PARAMETER TestIntegration
        dbatools's suite has unittests and integrationtests. This switch enables IntegrationTests, which need live instances
        see constants.ps1 for customizations

    .PARAMETER Coverage
        Enables measuring code coverage on the tested function

    .PARAMETER DependencyCoverage
        Enables measuring code coverage also of "lower level" (i.e. called) functions

    .PARAMETER ScriptAnalyzer
        Enables checking the called function's code with Invoke-ScriptAnalyzer, with dbatools's profile


    .EXAMPLE
        .\manual.pester.ps1 -Path Find-DbaOrphanedFile.Tests.ps1 -TestIntegration -Coverage -DependencyCovearge -ScriptAnalyzer

        The most complete number of checks:
          - Runs both unittests and integrationtests
          - Gathers and shows code coverage measurement for Find-DbaOrphanedFile and all its dependencies
          - Checks Find-DbaOrphanedFile with Invoke-ScriptAnalyzer

    .EXAMPLE
        .\manual.pester.ps1 -Path Find-DbaOrphanedFile.Tests.ps1

        Runs unittests stored in Find-DbaOrphanedFile.Tests.ps1

    .EXAMPLE
        .\manual.pester.ps1 -Path orphan

        Runs unittests for all tests matching in `*orphan*.Tests.ps1

    .EXAMPLE
        .\manual.pester.ps1 -Path Find-DbaOrphanedFile.Tests.ps1 -Show Default

        Runs unittests stored in Find-DbaOrphanedFile.Tests.ps1, with reduced verbosity

    .EXAMPLE
        .\manual.pester.ps1 -Path Find-DbaOrphanedFile.Tests.ps1 -TestIntegration

        Runs both unittests and integrationtests stored in Find-DbaOrphanedFile.Tests.ps1

    .EXAMPLE
        .\manual.pester.ps1 -Path Find-DbaOrphanedFile.Tests.ps1 -TestIntegration -Coverage

        Gathers and shows code coverage measurement for Find-DbaOrphanedFile

    .EXAMPLE
        .\manual.pester.ps1 -Path Find-DbaOrphanedFile.Tests.ps1 -TestIntegration -Coverage -DependencyCovearge

        Gathers and shows code coverage measurement for Find-DbaOrphanedFile and all its dependencies

#>

[CmdletBinding()]
param (
    [string[]]
    $Path,

    [ValidateSet('None', 'Default', 'Passed', 'Failed', 'Pending', 'Skipped', 'Inconclusive', 'Describe', 'Context', 'Summary', 'Header', 'All', 'Fails')]
    [string]
    $Show = "All",

    [switch]
    $TestIntegration,

    [switch]
    $Coverage,

    [switch]
    $DependencyCoverage,

    [switch]
    $ScriptAnalyzer
)

$HasScriptAnalyzer = $null -ne (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue).Version
$HasPester = $null -ne (Get-Command Invoke-Pester -ErrorAction SilentlyContinue).Version

if (!($HasScriptAnalyzer)) {
    Write-Warning "Please install PSScriptAnalyzer"
    Write-Warning "     Install-Module -Name PSScriptAnalyzer"
    Write-Warning "     or go to https://github.com/PowerShell/PSScriptAnalyzer"
}
if (!($HasPester)) {
    Write-Warning "Please install PSScriptAnalyzer"
    Write-Warning "     Install-Module -Name Pester -Force -SkipPublisherCheck"
    Write-Warning "     or go to https://github.com/pester/Pester"
}

if (($HasPester -and $HasScriptAnalyzer) -eq $false) {
    Write-Warning "Exiting..."
    return
}

$ModuleBase = Split-Path -Path $PSScriptRoot -Parent

$global:dbatools_dotsourcemodule = $true

#removes previously imported dbatools, if any
Remove-Module dbatools -ErrorAction Ignore
#imports the module making sure DLL is loaded ok
Import-Module "$ModuleBase\dbatools.psd1" -DisableNameChecking
#imports the psm1 to be able to use internal functions in tests
Import-Module "$ModuleBase\dbatools.psm1" -DisableNameChecking

$ScriptAnalyzerRulesExclude = @('PSUseOutputTypeCorrectly', 'PSAvoidUsingPlainTextForPassword')

$testInt = $false
if ($config_TestIntegration) {
    $testInt = $true
}
if ($TestIntegration) {
    $testInt = $true
}

function Get-CoverageIndications($Path, $ModuleBase) {
    # takes a test file path and figures out what to analyze for coverage (i.e. dependencies)
    $CBHRex = [regex]'(?smi)<#(.*)#>'
    $everything = (Get-Module dbatools).ExportedCommands.Values
    $everyfunction = $everything.Name
    $funcs = @()
    $leaf = Split-Path $path -Leaf
    # assuming Get-DbaFoo.Tests.ps1 wants coverage for "Get-DbaFoo"
    # but allowing also Get-DbaFoo.one.Tests.ps1 and Get-DbaFoo.two.Tests.ps1
    $func_name += ($leaf -replace '^([^.]+)(.+)?.Tests.ps1', '$1')
    if ($func_name -in $everyfunction) {
        $funcs += $func_name
        $f = $everything | Where-Object Name -eq $func_name
        $source = $f.Definition
        $CBH = $CBHRex.match($source).Value
        $cmdonly = $source.Replace($CBH, '')
        foreach ($e in $everyfunction) {
            # hacky, I know, but every occurrence of any function plus a space kinda denotes usage !?
            $searchme = "$e "
            if ($cmdonly.contains($searchme)) {
                $funcs += $e
            }
        }
    }
    $testpaths = @()
    $allfiles = Get-ChildItem -File -Path "$ModuleBase\internal", "$ModuleBase\functions" -Filter '*.ps1'
    foreach ($f in $funcs) {
        # exclude always used functions ?!
        if ($f -in ('Connect-SqlInstance', 'Select-DefaultView', 'Stop-Function', 'Write-Message')) { continue }
        # can I find a correspondence to a physical file (again, on the convenience of having Get-DbaFoo.ps1 actually defining Get-DbaFoo)?
        $res = $allfiles | Where-Object { $_.Name.Replace('.ps1', '') -eq $f }
        if ($res.count -gt 0) {
            $testpaths += $res.FullName
        }
    }
    return @() + ($testpaths | Select-Object -Unique)
}

$files = @()

if ($Path) {
    foreach ($item in $path) {
        if (Test-Path $item) {
            $files += Get-ChildItem -Path $item
        }
        else {
            $files += Get-ChildItem -Path "$ModuleBase\tests\*$item*.Tests.ps1"
        }
    }
}

if ($files.Length -eq 0) {
    Write-Warning "No tests to be run"
}

$AllTestsWithinScenario = $files

foreach ($f in $AllTestsWithinScenario) {
    $PesterSplat = @{
        'Script' = $f.FullName
        'Show'   = $show
    }
    #opt-in
    $HeadFunctionPath = $f.FullName

    if ($Coverage) {
        $CoverFiles = Get-CoverageIndications -Path $f -ModuleBase $ModuleBase
        $HeadFunctionPath = $CoverFiles | Select-Object -First 1

        if ($DependencyCoverage) {
            $CoverFilesPester = $CoverFiles
        }
        else {
            $CoverFilesPester = $HeadFunctionPath
        }
        $PesterSplat['CodeCoverage'] = $CoverFilesPester
    }
    if (!($testInt)) {
        $PesterSplat['ExcludeTag'] = "IntegrationTests"
    }
    Invoke-Pester @PesterSplat
    if ($ScriptAnalyzer) {
        if ($Show -ne "None") {
            Write-Host -ForegroundColor green -Object "ScriptAnalyzer check for $HeadFunctionPath"
        }
        Invoke-ScriptAnalyzer -Path $HeadFunctionPath -ExcludeRule $ScriptAnalyzerRulesExclude
    }
}
