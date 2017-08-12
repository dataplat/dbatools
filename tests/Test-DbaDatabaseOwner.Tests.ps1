$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$Name Tests"{
    InModuleScope 'dbatools' {
        Context "Connects to SQL Server" {
            It "Should not throw" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        Name = 'SQLServerName';
                        Databases = [object]@(
                            @{
                                Name = 'db1';
                                Status = 'Normal';
                                Owner = 'sa'
                            }
                        ); #databases
                        Logins = [object]@(
                            @{
                                ID = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-sqlserver
                
                { Test-DbaDatabaseOwner -SqlInstance 'SQLServerName' } | Should Not throw
            } #It
            It "Should not return if no wrong owner for default" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        Name = 'SQLServerName';
                        Databases = [object]@(
                            @{
                                Name = 'db1';
                                Status = 'Normal';
                                Owner = 'sa'
                            }
                        ); #databases
                        Logins = [object]@(
                            @{
                                ID = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-sqlserver
                
                { Test-DbaDatabaseOwner -SqlInstance 'SQLServerName' } | Should Not throw
            } #It
            It "Should return wrong owner information for one database with no owner specified" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        Name = 'SQLServerName';
                        Databases = [object]@(
                            @{
                                Name = 'db1';
                                Status = 'Normal';
                                Owner = 'WrongOWner'
                            }
                        ); #databases
                        Logins = [object]@(
                            @{
                                ID = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-sqlserver
                
                $Result = Test-DbaDatabaseOwner -SqlInstance 'SQLServerName'
                $Result.Server | Should Be 'SQLServerName'
                $Result.Database | Should Be 'db1';
                $Result.DBState | Should Be 'Normal';
                $Result.CurrentOwner | Should Be 'WrongOWner';
                $Result.TargetOwner | Should Be 'sa';
                $Result.OwnerMatch | Should Be $False
            } # it
            It "Should return information for one database with correct owner with detail parameter" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        Name = 'SQLServerName';
                        Databases = [object]@(
                            @{
                                Name = 'db1';
                                Status = 'Normal';
                                Owner = 'sa'
                            }
                        ); #databases
                        Logins = [object]@(
                            @{
                                ID = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-sqlserver
                
                $Result = Test-DbaDatabaseOwner -SqlInstance 'SQLServerName' -Detailed
                $Result.Server | Should Be 'SQLServerName'
                $Result.Database | Should Be 'db1';
                $Result.DBState | Should Be 'Normal';
                $Result.CurrentOwner | Should Be 'sa';
                $Result.TargetOwner | Should Be 'sa';
                $Result.OwnerMatch | Should Be $True
            } # it
            It "Should return wrong owner information for one database with no owner specified and multiple databases" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        Name = 'SQLServerName';
                        Databases = [object]@(
                            @{
                                Name = 'db1';
                                Status = 'Normal';
                                Owner = 'WrongOWner'
                            }
                            @{
                                Name = 'db2';
                                Status = 'Normal';
                                Owner = 'sa'
                            }
                        ); #databases
                        Logins = [object]@(
                            @{
                                ID = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-sqlserver
                
                $Result = Test-DbaDatabaseOwner -SqlInstance 'SQLServerName'
                $Result.Server | Should Be 'SQLServerName'
                $Result.Database | Should Be 'db1';
                $Result.DBState | Should Be 'Normal';
                $Result.CurrentOwner | Should Be 'WrongOWner';
                $Result.TargetOwner | Should Be 'sa';
                $Result.OwnerMatch | Should Be $False
            } # it
            It "Should return wrong owner information for two databases with no owner specified and multiple databases" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        Name = 'SQLServerName';
                        Databases = [object]@(
                            @{
                                Name = 'db1';
                                Status = 'Normal';
                                Owner = 'WrongOWner'
                            }
                            @{
                                Name = 'db2';
                                Status = 'Normal';
                                Owner = 'WrongOWner'
                            }
                        ); #databases
                        Logins = [object]@(
                            @{
                                ID = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-sqlserver
                
                $Result = Test-DbaDatabaseOwner -SqlInstance 'SQLServerName'
                $Result[0].Server | Should Be 'SQLServerName'
                $Result[1].Server | Should Be 'SQLServerName'
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
            It "Should notify if Target Login does not exist on Server" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        Name = 'SQLServerName';
                        Databases = [object]@(
                            @{
                                Name = 'db1';
                                Status = 'Normal';
                                Owner = 'WrongOWner'
                            }
                            @{
                                Name = 'db2';
                                Status = 'Normal';
                                Owner = 'WrongOWner'
                            }
                        ); #databases
                        Logins = [object]@(
                            @{
                                ID = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-sqlserver
                
                { Test-DbaDatabaseOwner -SqlInstance 'SQLServerName' -TargetLogin WrongLogin } | Should Throw 'Invalid login:'
            } # it
            It "Returns all information with detailed for correct and incorrect owner" {
                Mock Connect-SQLInstance -MockWith {
                    [object]@{
                        Name = 'SQLServerName';
                        Databases = [object]@(
                            @{
                                Name = 'db1';
                                Status = 'Normal';
                                Owner = 'WrongOWner'
                            }
                            @{
                                Name = 'db2';
                                Status = 'Normal';
                                Owner = 'sa'
                            }
                        ); #databases
                        Logins = [object]@(
                            @{
                                ID = 1;
                                Name = 'sa';
                            }
                        ) #logins
                    } #object
                } #mock connect-sqlserver
                
                $Result = Test-DbaDatabaseOwner -SqlInstance 'SQLServerName' -Detailed
                $Result[0].Server | Should Be 'SQLServerName'
                $Result[1].Server | Should Be 'SQLServerName'
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