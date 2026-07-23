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

    It "binds each piped computer to its own output record" {
        # Two computers down the pipeline must each produce their own result carrying their
        # own ComputerName; the implicit local-computer default must neither bleed across
        # records nor collapse the pair into a single output.
        $piped = @("localhost", $env:COMPUTERNAME | Test-DbaCmConnection -Type Wmi)
        $piped.Count | Should -Be 2
        $piped[0].ComputerName | Should -Be "localhost"
        $piped[1].ComputerName | Should -Be $env:COMPUTERNAME
    }

    It "registers each piped computer in the connection cache in input order" {
        # Every processed record registers its connection into the shared cache; a subsequent
        # read returns each requested computer, in the order requested, confirming per-record
        # registration is intact and the local-computer default did not displace them.
        $null = "localhost", $env:COMPUTERNAME | Test-DbaCmConnection -Type Wmi
        $cached = @(Get-DbaCmConnection -ComputerName localhost, $env:COMPUTERNAME)
        $cached.Count | Should -Be 2
        $cached[0].ComputerName | Should -Be "localhost"
        $cached[1].ComputerName | Should -Be $env:COMPUTERNAME
    }
}