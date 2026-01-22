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

    Context "Output Validation" {
        BeforeAll {
            . "$PSScriptRoot\..\private\functions\Get-SqlDefaultSPConfigure.ps1"
            $result2012 = Get-SqlDefaultSpConfigure -SqlVersion 11
            $result2000 = Get-SqlDefaultSpConfigure -SqlVersion 8
        }

        It "Returns PSCustomObject" {
            $result2012.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Contains common sp_configure properties across all versions" {
            $commonProps = @(
                "cost threshold for parallelism",
                "max degree of parallelism",
                "max server memory (MB)",
                "min server memory (MB)",
                "show advanced options"
            )
            $actualProps = $result2012.PSObject.Properties.Name
            foreach ($prop in $commonProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in SQL 2012"
            }
        }

        It "Returns different property counts for different SQL versions" {
            $count2012 = ($result2012 | Get-Member -MemberType NoteProperty).Count
            $count2000 = ($result2000 | Get-Member -MemberType NoteProperty).Count
            $count2012 | Should -BeGreaterThan $count2000 -Because "SQL 2012 has more configuration options than SQL 2000"
        }

        It "All property values are numeric or numeric defaults" {
            $result2012.PSObject.Properties | ForEach-Object {
                $_.Value | Should -BeOfType [System.Int32] -Because "all sp_configure defaults should be integers"
            }
        }
    }
}