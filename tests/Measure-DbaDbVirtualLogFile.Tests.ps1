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
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "IncludeSystemDBs",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
