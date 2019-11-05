$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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

            It 'Server under-report by 1 the memory installed on the host' {
                Mock Connect-SqlInstance {
                    return @{
                        PhysicalMemory = 1023
                    }
                }

                (Get-DbaMaxMemory -SqlInstance 'ABC').Total | Should be 1024
            }

            It 'Server reports correctly the memory installed on the host' {
                Mock Connect-SqlInstance {
                    return @{
                        PhysicalMemory = 1024
                    }
                }

                (Get-DbaMaxMemory -SqlInstance 'ABC').Total | Should be 1024
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

                (Get-DbaMaxMemory -SqlInstance 'ABC').MaxValue | Should be 2147483647
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
        It 'Returns the right amount of ' {
            $null = Set-DbaMaxMemory -SqlInstance $script:instance1, $script:instance2 -Max 1024
            $results = Get-DbaMaxMemory -SqlInstance $script:instance1
            $results.MaxValue | Should Be 1024
        }
    }
}