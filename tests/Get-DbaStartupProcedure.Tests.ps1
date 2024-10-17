param($ModuleName = 'dbatools')

Describe "Get-DbaStartupProcedure" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaStartupProcedure
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have StartupProcedure as a parameter" {
            $CommandUnderTest | Should -HaveParameter StartupProcedure -Type String[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $random = Get-Random
            $startupProc = "dbo.StartUpProc$random"
            $dbname = 'master'

            $null = $server.Query("CREATE PROCEDURE $startupProc AS Select 1", $dbname)
            $null = $server.Query("EXEC sp_procoption N'$startupProc', 'startup', '1'", $dbname)
        }
        AfterAll {
            $null = $server.Query("DROP PROCEDURE $startupProc", $dbname)
        }

        It "returns correct results" {
            $result = Get-DbaStartupProcedure -SqlInstance $script:instance2
            $result.Schema | Should -Be 'dbo'
            $result.Name | Should -Be "StartUpProc$random"
        }

        It "returns correct results for StartupProcedure parameter" {
            $result = Get-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure $startupProc
            $result.Schema | Should -Be 'dbo'
            $result.Name | Should -Be "StartUpProc$random"
        }

        It "returns null for incorrect StartupProcedure parameter" {
            $result = Get-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure 'Not.Here'
            $result | Should -BeNullOrEmpty
        }
    }
}
