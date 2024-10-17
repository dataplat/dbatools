param($ModuleName = 'dbatools')

Describe "Test-DbaMaxMemory" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaMaxMemory
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeAll {
            Mock Connect-DbaInstance -ModuleName $ModuleName -MockWith {
                "nothing"
            }

            Mock Get-DbaMaxMemory -ModuleName $ModuleName -MockWith {
                [PSCustomObject]@{
                    ComputerName = "SQL2016"
                    InstanceName = "MSSQLSERVER"
                    SqlInstance  = "SQL2016"
                    Total        = 4096
                    MaxValue     = 2147483647
                }
            }

            Mock Get-DbaService -ModuleName $ModuleName -MockWith {
                [PSCustomObject]@{
                    InstanceName = "foo"
                    State        = "Running"
                    ServiceType  = "Engine"
                }
            }
        }

        It "Connects to SQL Server" {
            Mock Get-DbaMaxMemory -ModuleName $ModuleName -MockWith { }

            $result = Test-DbaMaxMemory -SqlInstance 'ABC'

            Should -Invoke Connect-DbaInstance -ModuleName $ModuleName -Exactly -Times 1
            Should -Invoke Get-DbaService -ModuleName $ModuleName -Exactly -Times 1
            Should -Invoke Get-DbaMaxMemory -ModuleName $ModuleName -Exactly -Times 1
        }

        It "Connects to SQL Server and retrieves the 'Max Server Memory' setting" {
            Mock Get-DbaMaxMemory -ModuleName $ModuleName -MockWith {
                [PSCustomObject]@{ MaxValue = 2147483647 }
            }

            $result = Test-DbaMaxMemory -SqlInstance 'ABC'
            $result.MaxValue | Should -Be 2147483647
        }

        It "Calculates recommended memory - Single instance, Total 4GB, Expected 2GB, Reserved 2GB (.5x Memory)" {
            Mock Get-DbaMaxMemory -ModuleName $ModuleName -MockWith {
                [PSCustomObject]@{ Total = 4096 }
            }

            $result = Test-DbaMaxMemory -SqlInstance 'ABC'
            $result.InstanceCount | Should -Be 1
            $result.RecommendedValue | Should -Be 2048
        }

        It "Calculates recommended memory - Single instance, Total 6GB, Expected 3GB, Reserved 3GB (Iterations => 2x 8GB)" {
            Mock Get-DbaMaxMemory -ModuleName $ModuleName -MockWith {
                [PSCustomObject]@{ Total = 6144 }
            }

            $result = Test-DbaMaxMemory -SqlInstance 'ABC'
            $result.InstanceCount | Should -Be 1
            $result.RecommendedValue | Should -Be 3072
        }

        It "Calculates recommended memory - Single instance, Total 8GB, Expected 5GB, Reserved 3GB (Iterations => 2x 8GB)" {
            Mock Get-DbaMaxMemory -ModuleName $ModuleName -MockWith {
                [PSCustomObject]@{ Total = 8192 }
            }

            $result = Test-DbaMaxMemory -SqlInstance 'ABC'
            $result.InstanceCount | Should -Be 1
            $result.RecommendedValue | Should -Be 5120
        }

        It "Calculates recommended memory - Single instance, Total 16GB, Expected 11GB, Reserved 5GB (Iterations => 4x 8GB)" {
            Mock Get-DbaMaxMemory -ModuleName $ModuleName -MockWith {
                [PSCustomObject]@{ Total = 16384 }
            }

            $result = Test-DbaMaxMemory -SqlInstance 'ABC'
            $result.InstanceCount | Should -Be 1
            $result.RecommendedValue | Should -Be 11264
        }

        It "Calculates recommended memory - Single instance, Total 18GB, Expected 13GB, Reserved 5GB (Iterations => 1x 16GB, 3x 8GB)" {
            Mock Get-DbaMaxMemory -ModuleName $ModuleName -MockWith {
                [PSCustomObject]@{ Total = 18432 }
            }

            $result = Test-DbaMaxMemory -SqlInstance 'ABC'
            $result.InstanceCount | Should -Be 1
            $result.RecommendedValue | Should -Be 13312
        }

        It "Calculates recommended memory - Single instance, Total 32GB, Expected 25GB, Reserved 7GB (Iterations => 2x 16GB, 4x 8GB)" {
            Mock Get-DbaMaxMemory -ModuleName $ModuleName -MockWith {
                [PSCustomObject]@{ Total = 32768 }
            }

            $result = Test-DbaMaxMemory -SqlInstance 'ABC'
            $result.InstanceCount | Should -Be 1
            $result.RecommendedValue | Should -Be 25600
        }
    }

    Context "Error handling" {
        It "Throws an exception when no 'SQL Server' Windows service is running on the host" {
            Mock Get-DbaService -ModuleName $ModuleName -MockWith { $null }
            { Test-DbaMaxMemory -SqlInstance 'ABC' -EnableException } | Should -Throw
        }

        It "Throws an exception when SqlInstance parameter is empty" {
            Mock Get-DbaMaxMemory -ModuleName $ModuleName -MockWith { $null }
            { Test-DbaMaxMemory -SqlInstance '' } | Should -Throw
        }
    }

    Context "Raise warning when another component detected" {
        It "Should return a warning" {
            Mock Get-DbaService -ModuleName $ModuleName -MockWith {
                @(
                    [PSCustomObject]@{
                        InstanceName = "foo"
                        State        = "Running"
                        ServiceType  = "SSRS"
                    },
                    [PSCustomObject]@{
                        InstanceName = "foo"
                        State        = "Running"
                        ServiceType  = "Engine"
                    }
                )
            }
            Mock Connect-DbaInstance -ModuleName $ModuleName {
                $obj = [PSCustomObject]@{
                    Name                 = 'BASEName'
                    NetName              = 'BASENetName'
                    ComputerName         = 'BASEComputerName'
                    InstanceName         = 'BASEInstanceName'
                    DomainInstanceName   = 'BASEDomainInstanceName'
                    InstallDataDirectory = 'BASEInstallDataDirectory'
                    ErrorLogPath         = 'BASEErrorLog_{0}_{1}_{2}_Path' -f "'", '"', ']'
                    ServiceName          = 'BASEServiceName'
                    VersionMajor         = 12
                    ConnectionContext    = [PSCustomObject]@{
                        ConnectionString = 'put=an=equal=in=it'
                    }
                }
                $obj.PSObject.TypeNames.Clear()
                $obj.PSObject.TypeNames.Add("Microsoft.SqlServer.Management.Smo.Server")
                $obj
            }

            $result = Test-DbaMaxMemory -SqlInstance 'ABC' -WarningVariable warnvar -WarningAction SilentlyContinue
            $warnvar | Should -BeLike "*The memory calculation may be inaccurate as the following SQL components have also been detected*"
        }
    }
}
