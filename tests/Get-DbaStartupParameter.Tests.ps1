#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaStartupParameter",
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
                "Simple",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "WMI service validation" {
        It "Throws when the SQL Server service is not found" {
            Mock Invoke-ManagedComputerCommand -MockWith {
                param (
                    $Server,
                    $Credential,
                    $ScriptBlock,
                    $ArgumentList
                )
                $wmi = [PSCustomObject]@{
                    Services = @()
                }
                & $ScriptBlock @ArgumentList
            } -ModuleName dbatools

            { Get-DbaStartupParameter -SqlInstance "localhost" -EnableException } | Should -Throw
        }

        It "Throws when multiple SQL Server services match the instance name" {
            Mock Invoke-ManagedComputerCommand -MockWith {
                param (
                    $Server,
                    $Credential,
                    $ScriptBlock,
                    $ArgumentList
                )
                $serviceDisplayName = "SQL Server ($($ArgumentList[1]))"
                $wmi = [PSCustomObject]@{
                    Services = @(
                        [PSCustomObject]@{
                            DisplayName       = $serviceDisplayName
                            StartupParameters = "-dC:\SQLData\master.mdf;-lC:\SQLLog\mastlog.ldf;-eC:\SQLLog\ERRORLOG"
                        },
                        [PSCustomObject]@{
                            DisplayName       = $serviceDisplayName
                            StartupParameters = "-dD:\SQLData\master.mdf;-lD:\SQLLog\mastlog.ldf;-eD:\SQLLog\ERRORLOG"
                        }
                    )
                }
                & $ScriptBlock @ArgumentList
            } -ModuleName dbatools

            { Get-DbaStartupParameter -SqlInstance "localhost" -EnableException } | Should -Throw
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        It "Gets Results" {
            $results = Get-DbaStartupParameter -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }
        It "Simple parameter returns only essential properties" {
            $results = Get-DbaStartupParameter -SqlInstance $TestConfig.InstanceSingle -Simple
            $results | Should -Not -BeNullOrEmpty
            $properties = ($results | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) | Sort-Object
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "MasterData", "MasterLog", "ErrorLog", "TraceFlags", "DebugFlags", "ParameterString") | Sort-Object
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $properties | Should -BeNullOrEmpty
        }
        It "Without Simple parameter returns additional properties" {
            $results = Get-DbaStartupParameter -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
            $properties = $results | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
            $properties | Should -Contain "CommandPromptStart"
            $properties | Should -Contain "MinimalStart"
            $properties | Should -Contain "MemoryToReserve"
        }
    }
}