#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaEndpoint",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Endpoint",
                "ExcludeEndpoint",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Explain what needs to be set up for the test:
        # To test copying endpoints, we need to create a test endpoint on the source instance.

        # Set variables. They are available in all the It blocks.
        $endpointName = "dbatoolsci_MirroringEndpoint"
        $endpointPort = 5022

        # Create the objects.
        $splatEndpoint = @{
            SqlInstance     = $TestConfig.instance2
            Name            = $endpointName
            Type            = "DatabaseMirroring"
            Port            = $endpointPort
            Owner           = "sa"
            EnableException = $true
        }
        $null = New-DbaEndpoint @splatEndpoint

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance2 -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When copying endpoints between instances" {
        It "Successfully copies a mirroring endpoint" {
            $splatCopy = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                Endpoint    = $endpointName
            }
            $results = Copy-DbaEndpoint @splatCopy
            $results.DestinationServer | Should -Be $TestConfig.instance3
            $results.Status | Should -Be "Successful"
            $results.Name | Should -Be $endpointName
        }
    }
}