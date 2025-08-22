#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDbOwner",
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
                "Database",
                "ExcludeDatabase",
                "TargetLogin",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    InModuleScope 'dbatools' {
        Context "Connects to SQL Server" {
            It -Skip "Should not throw" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        Name      = 'SQLServerName';
                        Databases = [object]@(
                            @{
                                Name   = 'db1';
                                Status = 'Normal';
                                Owner  = 'sa'
                            }
                        ); #databases
                        Logins    = [object]@(
                            @{
                                ID   = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-SqlInstance

                {
                    Test-DbaDbOwner -SqlInstance 'SQLServerName'
                } | Should -Not -Throw
            } #It
            It -Skip "Should not return if no wrong owner for default" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        Name      = 'SQLServerName';
                        Databases = [object]@(
                            @{
                                Name   = 'db1';
                                Status = 'Normal';
                                Owner  = 'sa'
                            }
                        ); #databases
                        Logins    = [object]@(
                            @{
                                ID   = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-SqlInstance

                {
                    Test-DbaDbOwner -SqlInstance 'SQLServerName'
                } | Should -Not -Throw
            } #It
            It -Skip "Should return wrong owner information for one database with no owner specified" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        DomainInstanceName = 'SQLServerName';
                        Databases          = [object]@(
                            @{
                                Name   = 'db1';
                                Status = 'Normal';
                                Owner  = 'WrongOWner'
                            }
                        ); #databases
                        Logins             = [object]@(
                            @{
                                ID   = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-SqlInstance

                $Result = Test-DbaDbOwner -SqlInstance 'SQLServerName'
                $Result[0].SqlInstance | Should -Be 'SQLServerName'
                $Result[0].Database | Should -Be 'db1';
                $Result[0].DBState | Should -Be 'Normal';
                $Result[0].CurrentOwner | Should -Be 'WrongOWner';
                $Result[0].TargetOwner | Should -Be 'sa';
                $Result[0].OwnerMatch | Should -Be $False
            } # it
            It -Skip "Should return information for one database with correct owner with detail parameter" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        DomainInstanceName = 'SQLServerName';
                        Databases          = [object]@(
                            @{
                                Name   = 'db1';
                                Status = 'Normal';
                                Owner  = 'sa'
                            }
                        ); #databases
                        Logins             = [object]@(
                            @{
                                ID   = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-SqlInstance

                $Result = Test-DbaDbOwner -SqlInstance 'SQLServerName'
                $Result.SqlInstance | Should -Be 'SQLServerName'
                $Result.Database | Should -Be 'db1';
                $Result.DBState | Should -Be 'Normal';
                $Result.CurrentOwner | Should -Be 'sa';
                $Result.TargetOwner | Should -Be 'sa';
                $Result.OwnerMatch | Should -Be $True
            } # it
            It -Skip "Should return wrong owner information for one database with no owner specified and multiple databases" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        DomainInstanceName = 'SQLServerName';
                        Databases          = [object]@(
                            @{
                                Name   = 'db1';
                                Status = 'Normal';
                                Owner  = 'WrongOWner'
                            }
                            @{
                                Name   = 'db2';
                                Status = 'Normal';
                                Owner  = 'sa'
                            }
                        ); #databases
                        Logins             = [object]@(
                            @{
                                ID   = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-SqlInstance

                $Result = Test-DbaDbOwner -SqlInstance 'SQLServerName'
                $Result[0].SqlInstance | Should -Be 'SQLServerName'
                $Result[0].Database | Should -Be 'db1';
                $Result[0].DBState | Should -Be 'Normal';
                $Result[0].CurrentOwner | Should -Be 'WrongOWner';
                $Result[0].TargetOwner | Should -Be 'sa';
                $Result[0].OwnerMatch | Should -Be $False
            } # it
            It -Skip "Should return wrong owner information for two databases with no owner specified and multiple databases" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        DomainInstanceName = 'SQLServerName';
                        Databases          = [object]@(
                            @{
                                Name   = 'db1';
                                Status = 'Normal';
                                Owner  = 'WrongOWner'
                            }
                            @{
                                Name   = 'db2';
                                Status = 'Normal';
                                Owner  = 'WrongOWner'
                            }
                        ); #databases
                        Logins             = [object]@(
                            @{
                                ID   = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-SqlInstance

                $Result = Test-DbaDbOwner -SqlInstance 'SQLServerName'
                $Result[0].SqlInstance | Should -Be 'SQLServerName'
                $Result[1].SqlInstance | Should -Be 'SQLServerName'
                $Result[0].Database | Should -Be 'db1';
                $Result[1].Database | Should -Be 'db2';
                $Result[0].DBState | Should -Be 'Normal';
                $Result[1].DBState | Should -Be 'Normal';
                $Result[0].CurrentOwner | Should -Be 'WrongOWner';
                $Result[1].CurrentOwner | Should -Be 'WrongOWner';
                $Result[0].TargetOwner | Should -Be 'sa';
                $Result[1].TargetOwner | Should -Be 'sa';
                $Result[0].OwnerMatch | Should -Be $False
                $Result[1].OwnerMatch | Should -Be $False
            } # it

            It -Skip "Should call Stop-Function one time if Target Login does not exist on Server" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        DomainInstanceName = 'SQLServerName';
                        Databases          = [object]@(
                            @{
                                Name   = 'db1';
                                Status = 'Normal';
                                Owner  = 'WrongOwner'
                            }
                            @{
                                Name   = 'db2';
                                Status = 'Normal';
                                Owner  = 'WrongOwner'
                            }
                        ); #databases
                        Logins             = [object]@(
                            @{
                                ID   = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-SqlInstance
                Mock Stop-Function {
                }

                $null = Test-DbaDbOwner -SqlInstance 'SQLServerName' -TargetLogin 'WrongLogin'
                $assertMockParams = @{
                    'CommandName' = 'Stop-Function'
                    'Times'       = 1
                    'Exactly'     = $true
                }
                Assert-MockCalled @assertMockParams
            } # it
            It -Skip "Returns all information with detailed for correct and incorrect owner" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        DomainInstanceName = 'SQLServerName';
                        Databases          = [object]@(
                            @{
                                Name   = 'db1';
                                Status = 'Normal';
                                Owner  = 'WrongOWner'
                            }
                            @{
                                Name   = 'db2';
                                Status = 'Normal';
                                Owner  = 'sa'
                            }
                        ); #databases
                        Logins             = [object]@(
                            @{
                                ID   = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-SqlInstance

                $Result = Test-DbaDbOwner -SqlInstance 'SQLServerName'
                $Result[0].SqlInstance | Should -Be 'SQLServerName'
                $Result[1].SqlInstance | Should -Be 'SQLServerName'
                $Result[0].Database | Should -Be 'db1'
                $Result[1].Database | Should -Be 'db2'
                $Result[0].DBState | Should -Be 'Normal'
                $Result[1].DBState | Should -Be 'Normal'
                $Result[0].CurrentOwner | Should -Be 'WrongOWner'
                $Result[1].CurrentOwner | Should -Be 'sa'
                $Result[0].TargetOwner | Should -Be 'sa'
                $Result[1].TargetOwner | Should -Be 'sa'
                $Result[0].OwnerMatch | Should -Be $False
                $Result[1].OwnerMatch | Should -Be $true
            } # it
        } # Context
    } #modulescope
} #describe


Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        Get-DbaProcess -SqlInstance $TestConfig.instance1 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $dbname = "dbatoolsci_testdbowner"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $null = $server.Query("Create Database [$dbname]")
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname -Confirm:$false
    }

    Context "Command actually works" {
        It "Should return the correct information including database, currentowner and targetowner" {
            $whoami = whoami
            $results = Test-DbaDbOwner -SqlInstance $TestConfig.instance1 -Database $dbname
            $results.Database | Should -Be $dbname
            $results.CurrentOwner | Should -Be $whoami
            $results.TargetOwner | Should -Be 'sa'
        }
    }
}