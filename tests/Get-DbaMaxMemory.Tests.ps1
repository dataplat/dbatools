$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 3
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaMaxMemory).Parameters.Keys
        $knownParameters = 'SqlInstance','SqlCredential','EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Unit Test" -Tags Unittest {
    InModuleScope dbatools {
        Context 'Validate functionality ' {
            It 'Server SqlInstance reported correctly' {
                Mock Connect-SqlInstance {
                    return @{
                        DomainInstanceName = 'ABC'
                    }
                }

                (Get-DbaMaxMemory -SqlInstance 'ABC').SqlInstance | Should be 'ABC'
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

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Connects to multiple instances" {
        It 'Returns multiple objects' {
            $results = Get-DbaMaxMemory -SqlInstance $script:instance1, $script:instance2
            $results.Count | Should BeGreaterThan 1 # and ultimately not throw an exception
        }
        It 'Returns the right amount of MB' {
            $null = Set-DbaMaxMemory -SqlInstance $script:instance1, $script:instance2 -MaxMB 1024
            $results = Get-DbaMaxMemory -SqlInstance $script:instance1
            $results.SqlMaxMB | Should Be 1024
        }
    }
}