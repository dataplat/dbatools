param($ModuleName = 'dbatools')

Describe "Get-DbaDbDbccOpenTran" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbDbccOpenTran
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Gets results for Open Transactions" {
        BeforeAll {
            $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Cmd', 'Output', 'Field', 'Data'
            $result = Get-DbaDbDbccOpenTran -SqlInstance $global:instance1
        }

        It "returns results for DBCC OPENTRAN" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "returns multiple results" {
            $result.Count | Should -BeGreaterThan 0
        }

        It "Should return expected properties" {
            foreach ($prop in $props) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It "returns results for a specific database" {
            $tempDB = Get-DbaDatabase -SqlInstance $global:instance1 -Database tempDB
            $result = Get-DbaDbDbccOpenTran -SqlInstance $global:instance1 -Database tempDB

            $result | Should -Not -BeNullOrEmpty
            $result.Database | Get-Unique | Should -Be 'tempDB'
            $result.DatabaseId | Get-Unique | Should -Be $tempDB.Id
        }
    }
}
