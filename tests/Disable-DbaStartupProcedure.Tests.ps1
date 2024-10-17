param($ModuleName = 'dbatools')

Describe "Disable-DbaStartupProcedure" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disable-DbaStartupProcedure
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have StartupProcedure parameter" {
            $CommandUnderTest | Should -HaveParameter StartupProcedure -Type String[] -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $random = Get-Random
            $startupProcName = "StartUpProc$random"
            $startupProc = "dbo.$startupProcName"
            $dbname = 'master'

            $null = $server.Query("CREATE PROCEDURE $startupProc AS Select 1", $dbname)
            $null = $server.Query("EXEC sp_procoption '$startupProc', 'startup', 'on'", $dbname)
        }
        AfterAll {
            $null = $server.Query("DROP PROCEDURE $startupProc", $dbname)
        }

        It "Disables the startup procedure" {
            $result = Disable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Disable"
            $result.Status | Should -Be $true
            $result.Note | Should -Be "Disable succeded"
        }

        It "Returns correct output for already disabled procedure" {
            $result = Disable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Disable"
            $result.Status | Should -Be $false
            $result.Note | Should -Be "Action Disable already performed"
        }

        It "Disables startup procedure using piped input" {
            $null = Enable-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc -Confirm:$false
            $result = Get-DbaStartupProcedure -SqlInstance $global:instance2 | Disable-DbaStartupProcedure -Confirm:$false
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Disable"
            $result.Status | Should -Be $true
            $result.Note | Should -Be "Disable succeded"
        }
    }
}
