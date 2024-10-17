param($ModuleName = 'dbatools')

Describe "Get-DbaDbFileGroup" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $random = Get-Random
        $multifgdb = "dbatoolsci_multifgdb$random"
        Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database $multifgdb

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $server.Query("CREATE DATABASE $multifgdb; ALTER DATABASE $multifgdb ADD FILEGROUP [Test1]; ALTER DATABASE $multifgdb ADD FILEGROUP [Test2];")
    }

    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database $multifgdb
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbFileGroup
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Mandatory:$false
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[] -Mandatory:$false
        }
        It "Should have FileGroup parameter" {
            $CommandUnderTest | Should -HaveParameter FileGroup -Type String[] -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Returns values for Instance" {
        BeforeAll {
            $results = Get-DbaDbFileGroup -SqlInstance $global:instance2
        }
        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Returns the correct object" {
            $results[0].GetType().ToString() | Should -Be "Microsoft.SqlServer.Management.Smo.FileGroup"
        }
    }

    Context "Accepts database and filegroup input" {
        It "Reports the right number of filegroups" {
            $results = Get-DbaDbFileGroup -SqlInstance $global:instance2 -Database $multifgdb
            $results.Count | Should -Be 3
        }

        It "Reports the right number of filegroups when filtering" {
            $results = Get-DbaDbFileGroup -SqlInstance $global:instance2 -Database $multifgdb -FileGroup Test1
            $results.Count | Should -Be 1
        }
    }

    Context "Accepts piped input" {
        BeforeAll {
            $results = Get-DbaDatabase -SqlInstance $global:instance2 -ExcludeUser | Get-DbaDbFileGroup
        }
        It "Reports the right number of filegroups" {
            $results.Count | Should -Be 4
        }

        It "Excludes User Databases" {
            $results.Parent.Name | Should -Not -Contain $multifgdb
            $results.Parent.Name | Should -Contain 'msdb'
        }
    }
}
