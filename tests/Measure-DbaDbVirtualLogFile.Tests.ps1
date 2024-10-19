param($ModuleName = 'dbatools')

Describe "Measure-DbaDbVirtualLogFile" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Measure-DbaDbVirtualLogFile
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have IncludeSystemDBs as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDBs
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $db1 = "dbatoolsci_testvlf"
            $server.Query("CREATE DATABASE $db1")
            $needed = Get-DbaDatabase -SqlInstance $global:instance2 -Database $db1
        }

        AfterAll {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database $db1
        }

        It "Should have correct properties" {
            $results = Measure-DbaDbVirtualLogFile -SqlInstance $global:instance2 -Database $db1
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Total', 'TotalCount', 'Inactive', 'Active', 'LogFileName', 'LogFileGrowth', 'LogFileGrowthType'
            $results[0].PSObject.Properties.Name | Should -Be $ExpectedProps
        }

        It "Should have database name of $db1" {
            $results = Measure-DbaDbVirtualLogFile -SqlInstance $global:instance2 -Database $db1
            $results.Database | Should -Be $db1
        }

        It "Should have values for Total property" {
            $results = Measure-DbaDbVirtualLogFile -SqlInstance $global:instance2 -Database $db1
            $results.Total | Should -Not -BeNullOrEmpty
            $results.Total | Should -BeGreaterThan 0
        }
    }
}
