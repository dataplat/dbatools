#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Test-DbaCmConnection",
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
                "Type",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        Context "Timeout option initialization" {
            It "Initializes CIM session options when they are missing" {
                Mock Get-WmiObject {
                    [PSCustomObject]@{
                        Name = "mocked"
                    }
                }

                Mock New-DbaCimSessionOptionWithTimeout {
                    if ($Protocol -eq "Default") {
                        New-CimSessionOption -Protocol Default
                    } else {
                        New-CimSessionOption -Protocol Dcom
                    }
                }

                $connection = New-Object -TypeName Dataplat.Dbatools.Connection.ManagementConnection -ArgumentList "localhost"
                $inputObject = New-Object -TypeName Dataplat.Dbatools.Parameter.DbaCmConnectionParameter -ArgumentList $connection

                $result = Test-DbaCmConnection -ComputerName $inputObject -Type Wmi

                $result.CimWinRMOptions | Should -Not -BeNullOrEmpty
                $result.CimDCOMOptions | Should -Not -BeNullOrEmpty
                Assert-MockCalled New-DbaCimSessionOptionWithTimeout -Exactly 1 -Scope It -ParameterFilter { $Protocol -eq "Default" }
                Assert-MockCalled New-DbaCimSessionOptionWithTimeout -Exactly 1 -Scope It -ParameterFilter { $Protocol -eq "Dcom" }
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    It "returns some valid info" {
        $results = Test-DbaCmConnection -Type Wmi
        $results.ComputerName | Should -Be $env:COMPUTERNAME
    }
}