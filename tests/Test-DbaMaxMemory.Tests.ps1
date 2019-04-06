$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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
                    Total        = 4096
                    MaxValue     = 2147483647
                }
            }

            Mock Get-DbaService -MockWith {
                New-Object PSObject -Property @{
                    InstanceName = "foo"
                    State        = "Running"
                }
            }

            It 'Connect to SQL Server' {
                Mock Get-DbaMaxMemory -MockWith { }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'

                Assert-MockCalled Connect-SqlInstance -Scope It -Times 1
                Assert-MockCalled Get-DbaService -Scope It -Times 1
                Assert-MockCalled Get-DbaMaxMemory -Scope It -Times 1
            }

            It 'Connect to SQL Server and retrieve the "Max Server Memory" setting' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ MaxValue = 2147483647 }
                }

                (Test-DbaMaxMemory -SqlInstance 'ABC').MaxValue | Should be 2147483647
            }

            It 'Calculate recommended memory - Single instance, Total 4GB, Expected 2GB, Reserved 2GB (.5x Memory)' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 4096 }
                }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedValue | Should Be 2048
            }

            It 'Calculate recommended memory - Single instance, Total 6GB, Expected 3GB, Reserved 3GB (Iterations => 2x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 6144 }
                }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedValue | Should Be 3072
            }

            It 'Calculate recommended memory - Single instance, Total 8GB, Expected 5GB, Reserved 3GB (Iterations => 2x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 8192 }
                }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedValue | Should Be 5120
            }

            It 'Calculate recommended memory - Single instance, Total 16GB, Expected 11GB, Reserved 5GB (Iterations => 4x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 16384 }
                }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedValue | Should Be 11264
            }

            It 'Calculate recommended memory - Single instance, Total 18GB, Expected 13GB, Reserved 5GB (Iterations => 1x 16GB, 3x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 18432 }
                }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedValue | Should Be 13312
            }

            It 'Calculate recommended memory - Single instance, Total 32GB, Expected 25GB, Reserved 7GB (Iterations => 2x 16GB, 4x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 32768 }
                }

                $result = Test-DbaMaxMemory -SqlInstance 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedValue | Should Be 25600
            }
        }
    }
}