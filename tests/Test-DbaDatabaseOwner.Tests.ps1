Describe "$Name Tests"{
    InModuleScope 'dbatools' {
        Context "Connects to SQL Server" {
            It "Should not throw" {
                Mock Connect-SQLServer -MockWith {
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
                
                mock Get-ParamSqlDatabases -MockWith {
                    [object]@(
                        @{
                            Name = 'db1'
                        }
                    );
                    
                } #mock params
                { Test-DbaDatabaseOwner -SqlServer 'SQLServerName' } | Should Not throw
            } #It
            It "Should not return if no wrong owner for default" {
                Mock Connect-SQLServer -MockWith {
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
                
                mock Get-ParamSqlDatabases -MockWith {
                    [object]@(
                        @{
                            Name = 'db1'
                        }
                    );
                    
                } #mock params
                { Test-DbaDatabaseOwner -SqlServer 'SQLServerName' } | Should Not throw
            } #It
            It "Should return wrong owner information for one database with no owner specified" {
                Mock Connect-SQLServer -MockWith {
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
                
                mock Get-ParamSqlDatabases -MockWith {
                    [object]@(
                        @{
                            Name = 'db1'
                        }
                    );
                    
                } #mock params
                $Result = Test-DbaDatabaseOwner -SqlServer 'SQLServerName'
                $Result.Server | Should Be 'SQLServerName'
                $Result.Database | Should Be 'db1';
                $Result.DBState | Should Be 'Normal';
                $Result.CurrentOwner | Should Be 'WrongOWner';
                $Result.TargetOwner | Should Be 'sa';
                $Result.OwnerMatch | Should Be $False
            } # it
            It "Should return information for one database with correct owner with detail parameter" {
                Mock Connect-SQLServer -MockWith {
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
                
                mock Get-ParamSqlDatabases -MockWith {
                    [object]@(
                        @{
                            Name = 'db1'
                        }
                    );
                    
                } #mock params
                $Result = Test-DbaDatabaseOwner -SqlServer 'SQLServerName' -Detailed
                $Result.Server | Should Be 'SQLServerName'
                $Result.Database | Should Be 'db1';
                $Result.DBState | Should Be 'Normal';
                $Result.CurrentOwner | Should Be 'sa';
                $Result.TargetOwner | Should Be 'sa';
                $Result.OwnerMatch | Should Be $True
            } # it
            It "Should return wrong owner information for one database with no owner specified and multiple databases" {
                Mock Connect-SQLServer -MockWith {
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
                
                mock Get-ParamSqlDatabases -MockWith {
                    [object]@(
                        @{
                            Name = 'db1'
                        }
                    );
                    
                } #mock params
                $Result = Test-DbaDatabaseOwner -SqlServer 'SQLServerName'
                $Result.Server | Should Be 'SQLServerName'
                $Result.Database | Should Be 'db1';
                $Result.DBState | Should Be 'Normal';
                $Result.CurrentOwner | Should Be 'WrongOWner';
                $Result.TargetOwner | Should Be 'sa';
                $Result.OwnerMatch | Should Be $False
            } # it
            It "Should return wrong owner information for two databases with no owner specified and multiple databases" {
                Mock Connect-SQLServer -MockWith {
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
                
                mock Get-ParamSqlDatabases -MockWith {
                    [object]@(
                        @{
                            Name = 'db1'
                        }
                    );
                    
                } #mock params
                $Result = Test-DbaDatabaseOwner -SqlServer 'SQLServerName'
                $Result.Server | Should Be 'SQLServerName'
                $Result[0].Database | Should Be 'db1';
                $Result[1].Database | Should Be 'db2';
                $Result.DBState | Should Be 'Normal';
                $Result.CurrentOwner | Should Be 'WrongOWner';
                $Result.TargetOwner | Should Be 'sa';
                $Result.OwnerMatch | Should Be $False
            } # it
            It "Should notify if Target Login does not exist on Server" {
                Mock Connect-SQLServer -MockWith {
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
                
                mock Get-ParamSqlDatabases -MockWith {
                    [object]@(
                        @{
                            Name = 'db1'
                        }
                    );
                    
                } #mock params
                { Test-DbaDatabaseOwner -SqlServer 'SQLServerName' -TargetLogin WrongLogin } | Should Throw 'Invalid login:'
            } # it
            It "Returns all information with detailed for correct and incorrect owner" {
                Mock Connect-SQLServer -MockWith {
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
                
                mock Get-ParamSqlDatabases -MockWith {
                    [object]@(
                        @{
                            Name = 'db1'
                        }
                    );
                    
                } #mock params
                $Result = Test-DbaDatabaseOwner -SqlServer 'SQLServerName' -Detailed
                $Result.Server | Should Be 'SQLServerName';
                $Result[0].Database | Should Be 'db1';
                $Result[1].Database | Should Be 'db2';
                $Result.DBState | Should Be 'Normal';
                $Result[0].CurrentOwner | Should Be 'WrongOWner';
                $Result[1].CurrentOwner | Should Be 'sa';
                $Result.TargetOwner | Should Be 'sa';
                $Result[0].OwnerMatch | Should Be $False
                $Result[1].OwnerMatch | Should Be $true
            } # it
        } # Context
    } #modulescope
} #describe


