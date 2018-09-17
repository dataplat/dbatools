$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Connects to multiple instances" {
        It 'Returns multiple objects' {
            $results = Test-DbaMaxMemory -SqlInstance $script:instance1, $script:instance2
            $results.Count | Should BeGreaterThan 1 # and ultimately not throw an exception
        }
    }
}

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    InModuleScope dbatools {
        Context 'Validate input arguments' {
            It 'No "SQL Server" Windows service is running on the host' {
                { Test-DbaMaxMemory -SqlInstance 'ABC' -EnableException } | Should Throw
            }

            It 'SqlInstance parameter is empty throws an exception' {
                Mock Get-DbaMaxMemory -MockWith { return $null }
                { Test-DbaMaxMemory -SqlInstance '' } | Should Throw
            }

            It 'SqlInstance parameter host cannot be found' {
                Mock Get-DbaMaxMemory -MockWith { return $null }
                Test-DbaMaxMemory -SqlInstance 'ABC' 3> $null | Should be $null
            }

        }

        Context 'Validate functionality - Single Instance' {
            Mock Connect-SqlInstance -MockWith {
                "nothing"
            }

            Mock Get-DbaMaxMemory -MockWith {
                New-Object PSObject -Property @{
                    ComputerName = "SQL2016"
                    InstanceName = "MSSQLSERVER"
                    SqlInstance  = "SQL2016"
                    TotalMB      = 4096
                    SqlMaxMB     = 2147483647
                }
            }

            Mock Get-DbaSqlService -MockWith {
                New-Object PSObject -Property @{
                    InstanceName = "foo"
                    State        = "Running"
                }
            }

            It 'Connect to SQL Server' {
                Mock Get-DbaMaxMemory -MockWith { }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'

                Assert-MockCalled Connect-SqlInstance -Scope It -Times 1
                Assert-MockCalled Get-DbaSqlService -Scope It -Times 1
                Assert-MockCalled Get-DbaMaxMemory -Scope It -Times 1
            }

            It 'Connect to SQL Server and retrieve the "Max Server Memory" setting' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ SqlMaxMB = 2147483647 }
                }

                (Test-DbaMaxMemory -SqlInstance 'ABC').SqlMaxMB | Should be 2147483647
            }

            It 'Calculate recommended memory - Single instance, Total 4GB, Expected 2GB, Reserved 2GB (.5x Memory)' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ TotalMB = 4096 }
                }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedMB | Should Be 2048
            }

            It 'Calculate recommended memory - Single instance, Total 6GB, Expected 3GB, Reserved 3GB (Iterations => 2x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ TotalMB = 6144 }
                }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedMB | Should Be 3072
            }

            It 'Calculate recommended memory - Single instance, Total 8GB, Expected 5GB, Reserved 3GB (Iterations => 2x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ TotalMB = 8192 }
                }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedMB | Should Be 5120
            }

            It 'Calculate recommended memory - Single instance, Total 16GB, Expected 11GB, Reserved 5GB (Iterations => 4x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ TotalMB = 16384 }
                }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedMB | Should Be 11264
            }

            It 'Calculate recommended memory - Single instance, Total 18GB, Expected 13GB, Reserved 5GB (Iterations => 1x 16GB, 3x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ TotalMB = 18432 }
                }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedMB | Should Be 13312
            }

            It 'Calculate recommended memory - Single instance, Total 32GB, Expected 25GB, Reserved 7GB (Iterations => 2x 16GB, 4x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ TotalMB = 32768 }
                }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedMB | Should Be 25600
            }
        }
    }
}
