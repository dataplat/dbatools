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
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[] -Mandatory:$false
        }
        It "Should have IncludeSystemDBs as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDBs -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
