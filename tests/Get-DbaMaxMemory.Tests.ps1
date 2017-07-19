Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
Describe "Get-DbaMaxMemory Unit Tests" -Tag 'Unittests' {
    InModuleScope dbatools {
        Context 'Validate input arguments' {
            It 'SqlServer parameter is empty' {
                Mock Connect-SqlInstance { throw System.Data.SqlClient.SqlException }
                { Get-DbaMaxMemory -SqlInstance '' -WarningAction Stop 3> $null } | Should Throw
            }
            
            It 'SqlServer parameter host cannot be found' {
                Mock Connect-SqlInstance { throw System.Data.SqlClient.SqlException }
                { Get-DbaMaxMemory -SqlInstance 'ABC' -WarningAction Stop 3> $null } | Should Throw
            }
        }
        
        Context 'Validate functionality ' {
            It 'Server name reported correctly the installed memory' {
                Mock Connect-SqlInstance {
                    return @{
                        Name = 'ABC'
                    }
                }
                
                (Get-DbaMaxMemory -SqlInstance 'ABC').Server | Should be 'ABC'
            }
            
            It 'Server under-report by 1MB the memory installed on the host' {
                Mock Connect-SqlInstance {
                    return @{
                        PhysicalMemory = 1023
                    }
                }
                
                (Get-DbaMaxMemory -SqlInstance 'ABC').TotalMB | Should be 1024
            }
            
            It 'Server reports correctly the memory installed on the host' {
                Mock Connect-SqlInstance {
                    return @{
                        PhysicalMemory = 1024
                    }
                }
                
                (Get-DbaMaxMemory -SqlInstance 'ABC').TotalMB | Should be 1024
            }
            
            It 'Memory allocated to SQL Server instance reported' {
                Mock Connect-SqlInstance {
                    return @{
                        Configuration = @{
                            MaxServerMemory = @{
                                ConfigValue = 2147483647
                            }
                        }
                    }
                }
                
                (Get-DbaMaxMemory -SqlInstance 'ABC').SqlMaxMB | Should be 2147483647
            }
        }
    }
}
