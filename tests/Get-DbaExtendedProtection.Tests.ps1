#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaExtendedProtection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Accepted SPNs" {
            BeforeEach {
                Mock Resolve-DbaNetworkName {
                    [PSCustomObject]@{ FullComputerName = "sql1" }
                }
                Mock Invoke-ManagedComputerCommand {
                    [PSCustomObject]@{
                        DisplayName        = "SQL Server (MSSQLSERVER)"
                        ServiceAccount     = "NT Service\MSSQLSERVER"
                        AdvancedProperties = @(
                            [PSCustomObject]@{ Name = "REGROOT"; Value = "Software\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER" },
                            [PSCustomObject]@{ Name = "VSNAME"; Value = "sql1" }
                        )
                    }
                }
                Mock Get-ItemProperty {
                    [PSCustomObject]@{
                        ExtendedProtection = 1
                        AcceptedSPNs       = "MSSQLSvc/sql1.domain.local:1433;MSSQLSvc/sql1:1433"
                    }
                }
                Mock Invoke-Command2 {
                    & $ScriptBlock @ArgumentList
                }
                Mock Stop-Function { throw $Message }
            }

            It "returns accepted SPNs as individual values" {
                $result = Get-DbaExtendedProtection -SqlInstance "sql1" -Confirm:$false

                $result.AcceptedSpns | Should -Be @("MSSQLSvc/sql1.domain.local:1433", "MSSQLSvc/sql1:1433")
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    It "returns a value" {
        $results = Get-DbaExtendedProtection $TestConfig.InstanceSingle -EnableException
        $results.ExtendedProtection | Should -Not -BeNullOrEmpty
    }
}
