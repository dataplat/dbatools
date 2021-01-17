$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'FileGroup', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $multifgdb = "dbatoolsci_multifgdb$random"
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $multifgdb

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.Query("CREATE DATABASE $multifgdb; ALTER DATABASE $multifgdb ADD FILEGROUP [Test1]; ALTER DATABASE $multifgdb ADD FILEGROUP [Test2];")
    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $multifgdb
    }

    Context "Returns values for Instance" {
        $results = Get-DbaDbFileGroup -SqlInstance $script:instance2
        It "Results are not empty" {
            $results | Should Not Be $Null
        }
        It "Returns the correct object" {
            $results[0].GetType().ToString() | Should Be "Microsoft.SqlServer.Management.Smo.FileGroup"
        }
    }

    Context "Accepts database and filegroup input" {
        $results = Get-DbaDbFileGroup -SqlInstance $script:instance2 -Database $multifgdb

        It "Reports the right number of filegroups" {
            $results.Count | Should Be 3
        }

        $results = Get-DbaDbFileGroup -SqlInstance $script:instance2 -Database $multifgdb -FileGroup Test1

        It "Reports the right number of filegroups" {
            $results.Count | Should Be 1
        }
    }

    Context "Accepts piped input" {
        $results = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeUser | Get-DbaDbFileGroup

        It "Reports the right number of filegroups" {
            $results.Count | Should Be 4
        }

        It "Excludes User Databases" {
            $results.Parent.Name | Should -Not -Contain $multifgdb
            $results.Parent.Name  | Should -Contain 'msdb'
        }
    }
}