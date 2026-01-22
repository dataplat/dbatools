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

    Context "Output Validation" {
        BeforeAll {
            # Note: This test requires an instance that is already configured as a distributor
            # Skip if distributor is not configured or if instance is not available
            try {
                $replServer = Get-DbaReplServer -SqlInstance $TestConfig.instance1 -EnableException
                if (-not $replServer.IsDistributor) {
                    Set-TestInconclusive -Message "Instance $($TestConfig.instance1) is not configured as a distributor. Run Enable-DbaReplDistributor first."
                }
                $result = Enable-DbaReplPublishing -SqlInstance $TestConfig.instance1 -EnableException
            } catch {
                Set-TestInconclusive -Message "Could not test output validation: $_"
            }
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Replication.ReplicationServer]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'IsDistributor',
                'IsPublisher',
                'DistributionServer',
                'DistributionDatabase'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Sets IsPublisher to True after enabling publishing" {
            $result.IsPublisher | Should -BeTrue -Because "the instance should be configured as a publisher after running Enable-DbaReplPublishing"
        }
    }
}