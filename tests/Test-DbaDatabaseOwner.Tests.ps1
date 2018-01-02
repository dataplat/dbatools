$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$Name Tests" {
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
                } #mock connect-sqlserver

                { Test-DbaDatabaseOwner -SqlInstance 'SQLServerName' } | Should Not throw
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
                } #mock connect-sqlserver

                { Test-DbaDatabaseOwner -SqlInstance 'SQLServerName' } | Should Not throw
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
                } #mock connect-sqlserver

                $Result = Test-DbaDatabaseOwner -SqlInstance 'SQLServerName'
                $Result[0].SqlInstance | Should Be 'SQLServerName'
                $Result[0].Database | Should Be 'db1';
                $Result[0].DBState | Should Be 'Normal';
                $Result[0].CurrentOwner | Should Be 'WrongOWner';
                $Result[0].TargetOwner | Should Be 'sa';
                $Result[0].OwnerMatch | Should Be $False
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
                } #mock connect-sqlserver

                $Result = Test-DbaDatabaseOwner -SqlInstance 'SQLServerName'
                $Result.SqlInstance | Should Be 'SQLServerName'
                $Result.Database | Should Be 'db1';
                $Result.DBState | Should Be 'Normal';
                $Result.CurrentOwner | Should Be 'sa';
                $Result.TargetOwner | Should Be 'sa';
                $Result.OwnerMatch | Should Be $True
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
                } #mock connect-sqlserver

                $Result = Test-DbaDatabaseOwner -SqlInstance 'SQLServerName'
                $Result[0].SqlInstance | Should Be 'SQLServerName'
                $Result[0].Database | Should Be 'db1';
                $Result[0].DBState | Should Be 'Normal';
                $Result[0].CurrentOwner | Should Be 'WrongOWner';
                $Result[0].TargetOwner | Should Be 'sa';
                $Result[0].OwnerMatch | Should Be $False
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
                } #mock connect-sqlserver

                $Result = Test-DbaDatabaseOwner -SqlInstance 'SQLServerName'
                $Result[0].SqlInstance | Should Be 'SQLServerName'
                $Result[1].SqlInstance | Should Be 'SQLServerName'
                $Result[0].Database | Should Be 'db1';
                $Result[1].Database | Should Be 'db2';
                $Result[0].DBState | Should Be 'Normal';
                $Result[1].DBState | Should Be 'Normal';
                $Result[0].CurrentOwner | Should Be 'WrongOWner';
                $Result[1].CurrentOwner | Should Be 'WrongOWner';
                $Result[0].TargetOwner | Should Be 'sa';
                $Result[1].TargetOwner | Should Be 'sa';
                $Result[0].OwnerMatch | Should Be $False
                $Result[1].OwnerMatch | Should Be $False
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
                } #mock connect-sqlserver
                Mock Stop-Function {}

                $null = Test-DbaDatabaseOwner -SqlInstance 'SQLServerName' -TargetLogin 'WrongLogin'
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
                } #mock connect-sqlserver

                $Result = Test-DbaDatabaseOwner -SqlInstance 'SQLServerName'
                $Result[0].SqlInstance | Should Be 'SQLServerName'
                $Result[1].SqlInstance | Should Be 'SQLServerName'
                $Result[0].Database | Should Be 'db1'
                $Result[1].Database | Should Be 'db2'
                $Result[0].DBState | Should Be 'Normal'
                $Result[1].DBState | Should Be 'Normal'
                $Result[0].CurrentOwner | Should Be 'WrongOWner'
                $Result[1].CurrentOwner | Should Be 'sa'
                $Result[0].TargetOwner | Should Be 'sa'
                $Result[1].TargetOwner | Should Be 'sa'
                $Result[0].OwnerMatch | Should Be $False
                $Result[1].OwnerMatch | Should Be $true
            } # it
        } # Context
    } #modulescope
} #describe