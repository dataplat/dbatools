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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $endpointName = "dbatoolsci_MirroringEndpoint"
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaEndpoint -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -EndPoint $endpointName -Confirm:$false
    }

    Context "When creating database mirroring endpoints" {
        BeforeAll {
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $results = New-DbaEndpoint -SqlInstance $TestConfig.instance2 -Type DatabaseMirroring -Role Partner -Name $endpointName -Confirm:$false | Start-DbaEndpoint -Confirm:$false
        }

        It "creates an endpoint of the db mirroring type" {
            $results.EndpointType | Should -Be "DatabaseMirroring"
        }

        It "creates it with the right owner" {
            $sa = Get-SaLoginName -SqlInstance $TestConfig.instance2
            $results.Owner | Should -Be $sa
        }
    }
}