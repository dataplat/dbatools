param($ModuleName = 'dbatools')

Describe "Get-DbaMaxMemory" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaMaxMemory
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Validate functionality" {
        BeforeAll {
            Mock Connect-DbaInstance -ModuleName $ModuleName {
                [PSCustomObject]@{
                    DomainInstanceName = 'ABC'
                    PhysicalMemory     = 1024
                    Configuration      = @{
                        MaxServerMemory = @{
                            ConfigValue = 2147483647
                        }
                    }
                }
            }
        }

        It "Server SqlInstance reported correctly" {
            (Get-DbaMaxMemory -SqlInstance 'ABC').SqlInstance | Should -Be 'ABC'
        }

        It "Server reports correctly the memory installed on the host" {
            (Get-DbaMaxMemory -SqlInstance 'ABC').Total | Should -Be 1024
        }

        It "Memory allocated to SQL Server instance reported" {
            (Get-DbaMaxMemory -SqlInstance 'ABC').MaxValue | Should -Be 2147483647
        }
    }

    Context "Connects to multiple instances" -Skip:($null -ne $env:CI) {
        BeforeAll {
            $instances = $global:instance1, $global:instance2
        }

        It 'Returns multiple objects' {
            $results = Get-DbaMaxMemory -SqlInstance $instances
            $results.Count | Should -BeGreaterThan 1
        }

        It 'Returns the right amount of memory' {
            $null = Set-DbaMaxMemory -SqlInstance $instances -Max 1024
            $results = Get-DbaMaxMemory -SqlInstance $global:instance1
            $results.MaxValue | Should -Be 1024
        }
    }
}
