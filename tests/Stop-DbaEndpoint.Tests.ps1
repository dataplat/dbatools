#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaEndpoint",
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
                "Endpoint",
                "AllEndpoints",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command execution and functionality" {
        AfterAll {
            # Restore endpoint to started state
            Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint 'TSQL Default TCP' | Start-DbaEndpoint
        }

        It "Should stop the endpoint" {
            # We want to run all commands in the setup with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint 'TSQL Default TCP' | Start-DbaEndpoint

            # We want to run all commands outside of the setup without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $endpoint = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint 'TSQL Default TCP'
            $results = $endpoint | Stop-DbaEndpoint -OutVariable "global:dbatoolsciOutput"
            $results.EndpointState | Should -Be 'Stopped'
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Endpoint]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Endpoint"
        }
    }
}