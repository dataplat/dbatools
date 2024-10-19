param($ModuleName = 'dbatools')

Describe "Test-DbaMaxDop" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaMaxDop
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $db1 = "dbatoolsci_testMaxDop"
            $server.Query("CREATE DATABASE $db1")
            $needed = Get-DbaDatabase -SqlInstance $global:instance2 -Database $db1
            $setupright = $null -ne $needed
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $global:instance2 -Database $db1 | Remove-DbaDatabase -Confirm:$false
        }

        It "Command works on SQL Server 2016 or higher instances" -Skip:(-not $setupright) {
            $results = Test-DbaMaxDop -SqlInstance $global:instance2

            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'DatabaseMaxDop', 'CurrentInstanceMaxDop', 'RecommendedMaxDop', 'Notes'
            $results | ForEach-Object {
                $_.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object | Should -Be ($ExpectedProps | Sort-Object)
            }

            ($results | Where-Object Database -eq $db1).Count | Should -Be 1
        }
    }
}
