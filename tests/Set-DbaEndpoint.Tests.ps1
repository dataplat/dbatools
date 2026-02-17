#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaEndpoint",
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
                "Owner",
                "Type",
                "AllEndpoints",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $endpointName = "dbatoolsci_testendpoint"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1

        # Create a test endpoint for modification
        $ep = New-Object Microsoft.SqlServer.Management.Smo.Endpoint($server, $endpointName)
        $ep.ProtocolType = [Microsoft.SqlServer.Management.Smo.ProtocolType]::Tcp
        $ep.EndpointType = [Microsoft.SqlServer.Management.Smo.EndpointType]::TSql
        $ep.Protocol.Tcp.ListenerPort = 33333
        $ep.Create()

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $epCleanup = $server.Endpoints[$endpointName]
        if ($epCleanup) { $epCleanup.Drop() }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When setting endpoint properties" {
        It "Should set the endpoint owner" {
            $splatEndpoint = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Endpoint    = $endpointName
                Owner       = "sa"
            }
            $result = Set-DbaEndpoint @splatEndpoint -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
            $result.Owner | Should -Be "sa"
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