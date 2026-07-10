#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaProductKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        Context "Reachable registry with an unreachable SQL instance" {
            BeforeAll {
                # The registry answers and reports one instance...
                Mock Get-DbaRegistryRoot {
                    [PSCustomObject]@{
                        ComputerName = "sql01"
                        InstanceName = "MSSQLSERVER"
                        SqlInstance  = "sql01"
                    }
                }
                # ...but the SQL instance itself does not answer, a NON-terminating connect failure that
                # leaves $server null (the normal reachable-registry + unreachable-instance production case).
                Mock Connect-DbaInstance { }
                # Keep the remote product-key read from touching a real machine.
                Mock Invoke-Command2 { }
            }

            It "raises a method-on-null error and emits no row (never a null-Version object)" {
                $rows = Get-DbaProductKey -ComputerName "sql01" -ErrorVariable keyErrors -ErrorAction SilentlyContinue
                # The bug emitted a row whose Version was null; correct behavior emits NO such row.
                @($rows | Where-Object { $null -eq $PSItem.Version }) | Should -BeNullOrEmpty
                $rows | Should -BeNullOrEmpty
                # ...and it surfaces as a method-on-null error (order-independent across editions).
                $keyErrors | Should -Not -BeNullOrEmpty
                ($keyErrors.Exception.Message -join "`n") | Should -BeLike "*null-valued expression*"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:AppVeyor {
    # Skip IntegrationTests on AppVeyor because they fail for unknown reasons.

    Context "Gets ProductKey for Instances on $(([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName)" {
        BeforeAll {
            $results = Get-DbaProductKey -ComputerName ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Version for each result" {
            foreach ($row in $results) {
                $row.Version | Should -Not -BeNullOrEmpty
            }
        }

        It "Should have Edition for each result" {
            foreach ($row in $results) {
                $row.Edition | Should -Not -BeNullOrEmpty
            }
        }

        It "Should have Key for each result" {
            foreach ($row in $results) {
                $row.Key | Should -Not -BeNullOrEmpty
            }
        }
    }
}