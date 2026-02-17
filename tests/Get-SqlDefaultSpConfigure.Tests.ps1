#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-SqlDefaultSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlVersion"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Try all versions of SQL" {
        BeforeAll {
            . "$PSScriptRoot\..\private\functions\Get-SqlDefaultSPConfigure.ps1"
            $versionName = @{
                8  = "2000"
                9  = "2005"
                10 = "2008/2008R2"
                11 = "2012"
                12 = "2014"
                13 = "2016"
                14 = "2017"
                15 = "2019"
                16 = "2022"
            }
            $allResults = @()
            foreach ($version in 8..16) {
                $results = Get-SqlDefaultSPConfigure -SqlVersion $version
                $allResults += [PSCustomObject]@{
                    Version     = $version
                    VersionName = $versionName.Item($version)
                    Results     = $results
                }
            }
            $global:dbatoolsciOutput = $allResults
        }

        It "Should return results for all supported SQL Server versions" {
            foreach ($entry in $allResults) {
                $entry.Results | Should -Not -BeNullOrEmpty -Because "version $($entry.VersionName) should return results"
            }
        }

        It "Should return PSCustomObject for all supported SQL Server versions" {
            foreach ($entry in $allResults) {
                $entry.Results.GetType().FullName | Should -Be "System.Management.Automation.PSCustomObject" -Because "version $($entry.VersionName) should return PSCustomObject"
            }
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0].Results | Should -BeOfType [PSCustomObject]
        }

        It "Should have common sp_configure properties across all versions" {
            $commonProperties = @(
                "cost threshold for parallelism",
                "max degree of parallelism",
                "max server memory (MB)",
                "min server memory (MB)",
                "fill factor (%)",
                "max worker threads",
                "network packet size (B)",
                "recovery interval (min)",
                "show advanced options",
                "user connections",
                "user options"
            )
            foreach ($entry in $global:dbatoolsciOutput) {
                $actualProperties = $entry.Results.PSObject.Properties.Name
                foreach ($prop in $commonProperties) {
                    $prop | Should -BeIn $actualProperties -Because "version $($entry.VersionName) should have property '$prop'"
                }
            }
        }

        It "Should have integer values for all properties" {
            foreach ($entry in $global:dbatoolsciOutput) {
                foreach ($prop in $entry.Results.PSObject.Properties) {
                    $prop.Value | Should -BeOfType [int] -Because "property '$($prop.Name)' in version $($entry.VersionName) should be an integer"
                }
            }
        }

        It "Should return results for all versions 8 through 16" {
            $global:dbatoolsciOutput.Count | Should -Be 9
            $global:dbatoolsciOutput.Version | Should -Be @(8, 9, 10, 11, 12, 13, 14, 15, 16)
        }
    }
}