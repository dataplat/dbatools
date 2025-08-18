#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaSpn",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When getting SPN information" {
        BeforeAll {
            Mock Resolve-DbaNetworkName {
                [PSCustomObject]@{
                    InputName        = $env:COMPUTERNAME
                    ComputerName     = $env:COMPUTERNAME
                    IPAddress        = "127.0.0.1"
                    DNSHostName      = $env:COMPUTERNAME
                    DNSDomain        = $env:COMPUTERNAME
                    Domain           = $env:COMPUTERNAME
                    DNSHostEntry     = $env:COMPUTERNAME
                    FQDN             = $env:COMPUTERNAME
                    FullComputerName = $env:COMPUTERNAME
                }
            }
            $global:results = Test-DbaSpn -ComputerName $env:COMPUTERNAME -WarningAction SilentlyContinue
        }

        It "Returns some results" {
            $null -ne $global:results.RequiredSPN | Should -Be $true
        }

        It "Has the required properties for all results" {
            foreach ($result in $global:results) {
                $result.RequiredSPN -match "MSSQLSvc" | Should -Be $true
                $result.Cluster -eq $false | Should -Be $true
                $result.TcpEnabled | Should -Be $true
                $result.IsSet -is [bool] | Should -Be $true
            }
        }
    }
}