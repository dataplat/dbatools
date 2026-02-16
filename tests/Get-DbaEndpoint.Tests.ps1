#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaEndpoint",
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
                "Type",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When connecting to SQL Server" {
        It "gets some endpoints" {
            $results = @(Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput")
            $results.Count | Should -BeGreaterThan 1
            $results.Name | Should -Contain "TSQL Default TCP"
        }

        It "gets one endpoint" {
            $results = @(Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint "TSQL Default TCP")
            $results.Name | Should -Be "TSQL Default TCP"
            $results.Count | Should -Be 1
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Endpoint]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ID",
                "Name",
                "EndpointState",
                "EndpointType",
                "Owner",
                "IsAdminEndpoint",
                "Fqdn",
                "IsSystemObject"
            )
            $defaultColumns = ($global:dbatoolsciOutput | Where-Object Name -eq "TSQL Default TCP").PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Endpoint"
        }
    }
}