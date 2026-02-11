#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaReplPublishing",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "SnapshotShare",
                "PublisherSqlLogin",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:($env:APPVEYOR) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Must enable distributor first before publishing
            $distDbName = "dbatoolsci_distpub_$(Get-Random)"
            $splatDistributor = @{
                SqlInstance          = $TestConfig.InstanceSingle
                DistributionDatabase = $distDbName
                Confirm              = $false
            }
            $null = Enable-DbaReplDistributor @splatDistributor

            $splatPublishing = @{
                SqlInstance = $TestConfig.InstanceSingle
                Confirm     = $false
            }
            $result = Enable-DbaReplPublishing @splatPublishing

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Disable-DbaReplPublishing -SqlInstance $TestConfig.InstanceSingle -Force -Confirm:$false -ErrorAction SilentlyContinue
            $null = Disable-DbaReplDistributor -SqlInstance $TestConfig.InstanceSingle -Force -Confirm:$false -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result.psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Replication.ReplicationServer"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "IsDistributor", "IsPublisher", "DistributionServer", "DistributionDatabase")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Shows the instance is configured as a publisher" {
            $result.IsPublisher | Should -BeTrue
        }
    }
}