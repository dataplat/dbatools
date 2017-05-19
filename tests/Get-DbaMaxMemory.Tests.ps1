Describe 'Get-DbaMaxMemory' {
    InModuleScope dbatools {
        Context 'Validate input arguments' {
            It 'SqlServer parameter is empty' {
                Mock Connect-SqlServer { throw System.Data.SqlClient.SqlException }
                { Get-DbaMaxMemory -SqlServer '' -WarningAction Stop 3> $null } | Should Throw
            }
            
            It 'SqlServer parameter host cannot be found' {
                Mock Connect-SqlServer { throw System.Data.SqlClient.SqlException }
                { Get-DbaMaxMemory -SqlServer 'ABC' -WarningAction Stop 3> $null } | Should Throw
            }
        }
        
        Context 'Validate functionality ' {
            It 'Server name reported correctly the installed memory' {
                Mock Connect-SqlServer {
                    return @{
                        Name = 'ABC'
                    }
                }
                
                (Get-DbaMaxMemory -SqlServer 'ABC').Server | Should be 'ABC'
            }
            
            It 'Server under-report by 1MB the memory installed on the host' {
                Mock Connect-SqlServer {
                    return @{
                        PhysicalMemory = 1023
                    }
                }
                
                (Get-DbaMaxMemory -SqlServer 'ABC').TotalMB | Should be 1024
            }
            
            It 'Server reports correctly the memory installed on the host' {
                Mock Connect-SqlServer {
                    return @{
                        PhysicalMemory = 1024
                    }
                }
                
                (Get-DbaMaxMemory -SqlServer 'ABC').TotalMB | Should be 1024
            }
            
            It 'Memory allocated to SQL Server instance reported' {
                Mock Connect-SqlServer {
                    return @{
                        Configuration = @{
                            MaxServerMemory = @{
                                ConfigValue = 2147483647
                            }
                        }
                    }
                }
                
                (Get-DbaMaxMemory -SqlServer 'ABC').SqlMaxMB | Should be 2147483647
            }
        }
    }
}
