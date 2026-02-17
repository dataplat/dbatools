#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaEndpoint",
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
                "Name",
                "Type",
                "Protocol",
                "Role",
                "EndpointEncryption",
                "EncryptionAlgorithm",
                "AuthenticationOrder",
                "Certificate",
                "IPAddress",
                "Port",
                "SslPort",
                "Owner",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $endpointName = "dbatoolsci_MirroringEndpoint"
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaEndpoint -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -EndPoint $endpointName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When creating database mirroring endpoints" {
        BeforeAll {
            $results = New-DbaEndpoint -SqlInstance $TestConfig.InstanceMulti1 -Type DatabaseMirroring -Role Partner -Name $endpointName -OutVariable "global:dbatoolsciOutput" | Start-DbaEndpoint
        }

        It "creates an endpoint of the db mirroring type" {
            $results.EndpointType | Should -Be "DatabaseMirroring"
        }

        It "creates it with the right owner" {
            $sa = Get-SaLoginName -SqlInstance $TestConfig.InstanceMulti1
            $results.Owner | Should -Be $sa
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
                "IPAddress",
                "Port",
                "EndpointState",
                "EndpointType",
                "Owner",
                "IsAdminEndpoint",
                "Fqdn",
                "IsSystemObject"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Endpoint"
        }
    }
}