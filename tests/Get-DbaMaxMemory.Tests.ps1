#Import-Module .\dbatools.psm1

InModuleScope dbatools {
    Describe 'Get-DbaMaxMemory' {
        Context 'Invalid SqlServer parameter' {
            Mock Connect-SqlServer { throw System.Data.SqlClient.SqlException }
        
            It 'SqlServer parameter is empty' {
                { Get-DbaMaxMemory -SqlServer '' -WarningAction Stop } | Should Throw
            }

            It 'SqlServer does not exist' {
                { Get-DbaMaxMemory -SqlServer 'ABC' -WarningAction Stop } | Should Throw
            }
        }

        Context 'Reported server name' {
            It 'Server reports correctly the installed memory' {
                Mock Connect-SqlServer { 
                    return @{
				        Name = 'ABC'
			        }
                } 
                
                (Get-DbaMaxMemory -SqlServer 'ABC').Server | Should be 'ABC'
            }  
        }

        Context 'Report memory of the host machine' {
            <#
            It 'Test Mock' {
                $server = Connect-SqlServer -SqlServer 'ABC'
                $server.Name | Should be 'ABC'
                $server.Configuration.MaxServerMemory.ConfigValue | Should be 2147483647
            }  
            #>
            
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
        }

        Context 'Report memory allocatated to SQL Server' {
            It 'Memory allocated to the instance' {
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