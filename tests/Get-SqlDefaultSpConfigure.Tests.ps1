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
            foreach ($version in 8..14) {
                $results = Get-SqlDefaultSPConfigure -SqlVersion $version
                $allResults += [PSCustomObject]@{
                    Version     = $version
                    VersionName = $versionName.Item($version)
                    Results     = $results
                }
            }
        }

        It "Should return results for <VersionName>" -ForEach $allResults {
            $Results | Should -Not -BeNullOrEmpty
        }

        It "Should return 'System.Management.Automation.PSCustomObject' object for <VersionName>" -ForEach $allResults {
            $Results.GetType().fullname | Should -Be "System.Management.Automation.PSCustomObject"
        }
    }
}