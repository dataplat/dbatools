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
            $results = $endpoint | Stop-DbaEndpoint
            $results.EndpointState | Should -Be 'Stopped'
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $PSDefaultParameterValues["*-Dba*:Confirm"] = $false

            # Create a database mirroring endpoint that we can safely stop without breaking connectivity
            $outputEndpointName = "dbatoolsci_stopep_$(Get-Random)"
            $null = New-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Name $outputEndpointName -Type DatabaseMirroring
            $null = Start-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $outputEndpointName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $outputResult = Stop-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $outputEndpointName -Confirm:$false
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:Confirm"] = $false
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $TestConfig.SqlCred
            $server.ConnectionContext.ExecuteNonQuery("IF EXISTS(SELECT 1 FROM sys.endpoints WHERE name = '$outputEndpointName') DROP ENDPOINT [$outputEndpointName]") | Out-Null
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Endpoint"
        }

        It "Has the expected default display properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ID",
                "Name",
                "IPAddress",
                "Port",
                "EndpointState",
                "EndpointType",
                "Owner",
                "IsAdminEndpoint",
                "Fqdn",
                "IsSystemObject"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}