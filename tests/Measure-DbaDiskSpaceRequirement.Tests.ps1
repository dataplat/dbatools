#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Measure-DbaDiskSpaceRequirement",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Database",
                "SourceSqlCredential",
                "Destination",
                "DestinationDatabase",
                "DestinationSqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Should Measure Disk Space Required" {
        BeforeAll {
            $server1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

            $splatMeasure = @{
                Source              = $TestConfig.InstanceCopy1
                Destination         = $TestConfig.InstanceCopy2
                Database            = "master"
                DestinationDatabase = "Dbatoolsci_DestinationDB"
            }
            $results = Measure-DbaDiskSpaceRequirement @splatMeasure
        }

        It "Should have information" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be sourced from Master" {
            $results[0].SourceDatabase | Should -Be $splatMeasure.Database
        }

        It "Should be sourced from the instance $($TestConfig.InstanceCopy1)" {
            $results[0].SourceSqlInstance | Should -Be $server1.SqlInstance
        }

        It "Should be destined for Dbatoolsci_DestinationDB" {
            $results[0].DestinationDatabase | Should -Be $splatMeasure.DestinationDatabase
        }

        It "Should be destined for the instance $($TestConfig.InstanceCopy2)" {
            $results[0].DestinationSqlInstance | Should -Be $server2.SqlInstance
        }

        It "Should have files on source" {
            $results[0].FileLocation | Should -Be "Only on Source"
        }
    }
}