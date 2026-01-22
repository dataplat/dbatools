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
            $results = New-DbaEndpoint -SqlInstance $TestConfig.InstanceMulti1 -Type DatabaseMirroring -Role Partner -Name $endpointName | Start-DbaEndpoint
        }

        It "creates an endpoint of the db mirroring type" {
            $results.EndpointType | Should -Be "DatabaseMirroring"
        }

        It "creates it with the right owner" {
            $sa = Get-SaLoginName -SqlInstance $TestConfig.InstanceMulti1
            $results.Owner | Should -Be $sa
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = New-DbaEndpoint -SqlInstance $TestConfig.InstanceMulti1 -Name "dbatoolsci_OutputTest" -Type DatabaseMirroring -EnableException
        }

        AfterAll {
            $null = Remove-DbaEndpoint -SqlInstance $TestConfig.InstanceMulti1 -EndPoint "dbatoolsci_OutputTest" -Confirm:$false
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Endpoint]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'ID',
                'Name',
                'IPAddress',
                'Port',
                'EndpointState',
                'EndpointType',
                'Owner',
                'IsAdminEndpoint',
                'Fqdn',
                'IsSystemObject'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}