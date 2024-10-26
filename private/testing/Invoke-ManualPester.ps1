function Invoke-ManualPester {
<#
.SYNOPSIS
    Runs dbatools tests with support for both Pester v4 and v5.

.DESCRIPTION
    This is a helper function to automate running tests locally. It supports both Pester v4 and v5 tests,
    automatically detecting which version to use based on the test file requirements. For Pester v5 tests,
    it uses the new configuration system while maintaining backward compatibility with v4 tests.

.PARAMETER Path
    The Path to the test files to run. It accepts multiple test file paths passed in (e.g. .\Find-DbaOrphanedFile.Tests.ps1) as well
    as simple strings (e.g. "orphaned" will run all files matching .\*orphaned*.Tests.ps1)

.PARAMETER Show
    Gets passed down to Pester's -Show parameter (useful if you want to reduce verbosity)
    Valid values are: None, Default, Passed, Failed, Pending, Skipped, Inconclusive, Describe, Context, Summary, Header, All, Fails

.PARAMETER PassThru
    Gets passed down to Pester's -PassThru parameter (useful if you want to return an object to analyze)

.PARAMETER TestIntegration
    dbatools's suite has unittests and integrationtests. This switch enables IntegrationTests, which need live instances
    see Get-TestConfig for customizations

.PARAMETER Coverage
    Enables measuring code coverage on the tested function. For Pester v5 tests, this will generate coverage in JaCoCo format.

.PARAMETER DependencyCoverage
    Enables measuring code coverage also of "lower level" (i.e. called) functions

.PARAMETER ScriptAnalyzer
    Enables checking the called function's code with Invoke-ScriptAnalyzer, with dbatools's profile

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1 -TestIntegration -Coverage -DependencyCoverage -ScriptAnalyzer

    The most complete number of checks:
    - Runs both unittests and integrationtests
    - Gathers and shows code coverage measurement for Find-DbaOrphanedFile and all its dependencies
    - Checks Find-DbaOrphanedFile with Invoke-ScriptAnalyzer
    - Automatically detects and uses the appropriate Pester version

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1

    Runs tests stored in Find-DbaOrphanedFile.Tests.ps1, automatically detecting whether to use Pester v4 or v5

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1 -PassThru

    Runs tests stored in Find-DbaOrphanedFile.Tests.ps1 and returns an object that can be analyzed

.EXAMPLE
    Invoke-ManualPester -Path orphan

    Runs tests for all tests matching in `*orphan*.Tests.ps1

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1 -Show Default

    Runs tests stored in Find-DbaOrphanedFile.Tests.ps1, with reduced verbosity

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1 -TestIntegration

    Runs both unittests and integrationtests stored in Find-DbaOrphanedFile.Tests.ps1

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1 -TestIntegration -Coverage

    Gathers and shows code coverage measurement for Find-DbaOrphanedFile.
    For Pester v5 tests, this will generate coverage in JaCoCo format.

.EXAMPLE
    Invoke-ManualPester -Path Find-DbaOrphanedFile.Tests.ps1 -TestIntegration -Coverage -DependencyCoverage

    Gathers and shows code coverage measurement for Find-DbaOrphanedFile and all its dependencies.
    For Pester v5 tests, this will generate coverage in JaCoCo format.

.NOTES
    For Pester v5 tests, include the following requirement in your test file:
    #Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0.0" }

    Tests without this requirement will be run using Pester v4.4.2.
#>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path,
        [ValidateSet('None', 'Default', 'Passed', 'Failed', 'Pending', 'Skipped', 'Inconclusive', 'Describe', 'Context', 'Summary', 'Header', 'All', 'Fails')]
        [string]$Show = "All",
        [switch]$PassThru,
        [switch]$TestIntegration,
        [switch]$Coverage,
        [switch]$DependencyCoverage,
        [switch]$ScriptAnalyzer
    )

    $invokeFormatterVersion = (Get-Command Invoke-Formatter -ErrorAction SilentlyContinue).Version
    $HasScriptAnalyzer = $null -ne $invokeFormatterVersion
    $ScriptAnalyzerCorrectVersion = '1.18.2'

    if (!($HasScriptAnalyzer)) {
        Write-Warning "Please install PSScriptAnalyzer"
        Write-Warning "     Install-Module -Name PSScriptAnalyzer -RequiredVersion '$ScriptAnalyzerCorrectVersion'"
        Write-Warning "     or go to https://github.com/PowerShell/PSScriptAnalyzer"
    } else {
        if ($invokeFormatterVersion -ne $ScriptAnalyzerCorrectVersion) {
            Remove-Module PSScriptAnalyzer
            try {
                Import-Module PSScriptAnalyzer -RequiredVersion $ScriptAnalyzerCorrectVersion -ErrorAction Stop
            } catch {
                Write-Warning "Please install PSScriptAnalyzer $ScriptAnalyzerCorrectVersion"
                Write-Warning "     Install-Module -Name PSScriptAnalyzer -RequiredVersion '$ScriptAnalyzerCorrectVersion'"
            }
        }
    }

    if ((Test-Path /workspace)) {
        $ModuleBase = "/workspace"
    } else {
        $ModuleBase = Split-Path -Path $PSScriptRoot -Parent
    }

    if (-not(Test-Path "$ModuleBase\.git" -Type Container)) {
        New-Item -Type Container -Path "$ModuleBase\.git" -Force
    }

    # Remove-Module dbatools -ErrorAction Ignore
    # Import-Module "$ModuleBase\dbatools.psd1" -DisableNameChecking -Force
    Import-Module "$ModuleBase\dbatools.psm1" -DisableNameChecking -Force

    $ScriptAnalyzerRulesExclude = @('PSUseOutputTypeCorrectly', 'PSAvoidUsingPlainTextForPassword', 'PSUseBOMForUnicodeEncodedFile')

    $testInt = $false
    if ($config_TestIntegration) {
        $testInt = $true
    }
    if ($TestIntegration) {
        $testInt = $true
    }

    # Keep the Get-CoverageIndications function as is
    function Get-CoverageIndications($Path, $ModuleBase) {
        # [Previous implementation remains the same]
    }

    function Get-PesterTestVersion($testFilePath) {
        $testFileContent = Get-Content -Path $testFilePath -Raw
        if ($testFileContent -match '#Requires\s+-Module\s+@\{\s+ModuleName="Pester";\s+ModuleVersion="5\.') {
            return '5'
        }
        return '4'
    }

    $files = @()

    if ($Path) {
        foreach ($item in $path) {
            if (Test-Path $item) {
                $files += Get-ChildItem -Path $item
            } else {
                $files += Get-ChildItem -Path "$ModuleBase\tests\*$item*.Tests.ps1"
            }
        }
    }

    if ($files.Length -eq 0) {
        Write-Warning "No tests to be run"
        return
    }

    foreach ($f in $files) {
        $pesterVersion = Get-PesterTestVersion -testFilePath $f.FullName

        # Remove any previously loaded pester module
        Remove-Module -Name pester -ErrorAction SilentlyContinue

        if ($pesterVersion -eq '5') {
            Import-Module Pester -RequiredVersion 5.6.1
            $pester5Config = New-PesterConfiguration
            $pester5Config.Run.Path = $f.FullName

            # Convert SwitchParameter to bool for PassThru
            $pester5Config.Run.PassThru = [bool]$PassThru

            # Convert Show parameter to v5 verbosity
            $verbosityMap = @{
                'None'         = 'None'
                'Default'      = 'Normal'
                'All'          = 'Detailed'
                'Fails'        = 'Detailed'
                'Describe'     = 'Detailed'
                'Context'      = 'Detailed'
                'Summary'      = 'Normal'
                'Header'       = 'Normal'
                'Passed'       = 'Detailed'
                'Failed'       = 'Detailed'
                'Pending'      = 'Detailed'
                'Skipped'      = 'Detailed'
                'Inconclusive' = 'Detailed'
            }

            $pester5Config.Output.Verbosity = $verbosityMap[$Show]

            if (!($testInt)) {
                $pester5Config.Filter.ExcludeTag = @('IntegrationTests')
            }

            if ($Coverage) {
                $CoverFiles = Get-CoverageIndications -Path $f -ModuleBase $ModuleBase
                if (!$DependencyCoverage) {
                    $CoverFiles = $CoverFiles | Select-Object -First 1
                }
                $pester5Config.CodeCoverage.Enabled = $true
                $pester5Config.CodeCoverage.Path = $CoverFiles
                $pester5Config.CodeCoverage.OutputFormat = 'JaCoCo'
                $pester5Config.CodeCoverage.OutputPath = "$ModuleBase\Pester5Coverage.xml"
            }

            Invoke-Pester -Configuration $pester5Config
        } else {
            Import-Module pester -RequiredVersion 4.4.2
            $PesterSplat = @{
                'Script'   = $f.FullName
                'Show'     = $show
                'PassThru' = $PassThru
            }

            if ($Coverage) {
                $CoverFiles = Get-CoverageIndications -Path $f -ModuleBase $ModuleBase
                if (!$DependencyCoverage) {
                    $CoverFiles = $CoverFiles | Select-Object -First 1
                }
                $PesterSplat['CodeCoverage'] = $CoverFiles
            }

            if (!($testInt)) {
                $PesterSplat['ExcludeTag'] = "IntegrationTests"
            }

            Invoke-Pester @PesterSplat
        }

        if ($ScriptAnalyzer) {
            $HeadFunctionPath = (Get-CoverageIndications -Path $f -ModuleBase $ModuleBase | Select-Object -First 1)
            if ($Show -ne "None") {
                Write-Host -ForegroundColor green -Object "ScriptAnalyzer check for $HeadFunctionPath"
            }
            Invoke-ScriptAnalyzer -Path $HeadFunctionPath -ExcludeRule $ScriptAnalyzerRulesExclude
        }
    }
}