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
                # $ScriptBlock was created inside the module, so invoking it directly would run it in the module scope, where $wmi is not visible.
                # Recreating it here binds it to this scope, so it can use the $wmi defined above.
                $localScriptBlock = [scriptblock]::Create($ScriptBlock.ToString())
                & $localScriptBlock @ArgumentList
            } -ModuleName dbatools

            { Get-DbaStartupParameter -SqlInstance "localhost" -EnableException } | Should -Throw -ExpectedMessage "*SQL Server service*was not found*"
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
                # $ScriptBlock was created inside the module, so invoking it directly would run it in the module scope, where $wmi is not visible.
                # Recreating it here binds it to this scope, so it can use the $wmi defined above.
                $localScriptBlock = [scriptblock]::Create($ScriptBlock.ToString())
                & $localScriptBlock @ArgumentList
            } -ModuleName dbatools

            { Get-DbaStartupParameter -SqlInstance "localhost" -EnableException } | Should -Throw -ExpectedMessage "*Multiple SQL Server services*were found*"
        }
    }

    Context "Startup parameter parsing" {
        BeforeAll {
            # The drive letters are lower case on purpose, because those are the ones that got lost in the past.
            Mock Invoke-ManagedComputerCommand -MockWith {
                param (
                    $Server,
                    $Credential,
                    $ScriptBlock,
                    $ArgumentList
                )
                $wmi = [PSCustomObject]@{
                    Services = @(
                        [PSCustomObject]@{
                            DisplayName       = "SQL Server ($($ArgumentList[1]))"
                            StartupParameters = "-dd:\SQLData\master.mdf;-ee:\SQLLog\ERRORLOG;-ll:\SQLLog\mastlog.ldf"
                        }
                    )
                }
                # $ScriptBlock was created inside the module, so invoking it directly would run it in the module scope, where $wmi is not visible.
                # Recreating it here binds it to this scope, so it can use the $wmi defined above.
                $localScriptBlock = [scriptblock]::Create($ScriptBlock.ToString())
                & $localScriptBlock @ArgumentList
            } -ModuleName dbatools
        }

        It "Keeps the drive letter of the paths with Simple" {
            $simpleResult = Get-DbaStartupParameter -SqlInstance "localhost" -Simple -EnableException

            $simpleResult.MasterData | Should -Be "d:\SQLData\master.mdf"
            $simpleResult.MasterLog | Should -Be "l:\SQLLog\mastlog.ldf"
            $simpleResult.ErrorLog | Should -Be "e:\SQLLog\ERRORLOG"
        }

        It "Keeps the drive letter of the paths without Simple" {
            $detailedResult = Get-DbaStartupParameter -SqlInstance "localhost" -EnableException

            $detailedResult.MasterData | Should -Be "d:\SQLData\master.mdf"
            $detailedResult.MasterLog | Should -Be "l:\SQLLog\mastlog.ldf"
            $detailedResult.ErrorLog | Should -Be "e:\SQLLog\ERRORLOG"
        }
    }

    Context "Startup parameters without a path to ERRORLOG" {
        BeforeAll {
            Mock Invoke-ManagedComputerCommand -MockWith {
                param (
                    $Server,
                    $Credential,
                    $ScriptBlock,
                    $ArgumentList
                )
                $wmi = [PSCustomObject]@{
                    Services = @(
                        [PSCustomObject]@{
                            DisplayName       = "SQL Server ($($ArgumentList[1]))"
                            StartupParameters = "-dd:\SQLData\master.mdf;-ll:\SQLLog\mastlog.ldf"
                        }
                    )
                }
                # $ScriptBlock was created inside the module, so invoking it directly would run it in the module scope, where $wmi is not visible.
                # Recreating it here binds it to this scope, so it can use the $wmi defined above.
                $localScriptBlock = [scriptblock]::Create($ScriptBlock.ToString())
                & $localScriptBlock @ArgumentList
            } -ModuleName dbatools
        }

        It "Returns an object with an empty ErrorLog instead of failing" {
            $noErrorLogResult = Get-DbaStartupParameter -SqlInstance "localhost" -Simple -EnableException

            $noErrorLogResult | Should -Not -BeNullOrEmpty
            $noErrorLogResult.MasterData | Should -Be "d:\SQLData\master.mdf"
            $noErrorLogResult.ErrorLog | Should -BeNullOrEmpty
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