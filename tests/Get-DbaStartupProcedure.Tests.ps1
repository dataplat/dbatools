param($ModuleName = 'dbatools')

Describe "Get-DbaStartupProcedure" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaStartupProcedure
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "StartupProcedure",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
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
            $result = Get-DbaStartupProcedure -SqlInstance $global:instance2
            $result.Schema | Should -Be 'dbo'
            $result.Name | Should -Be "StartUpProc$random"
        }

        It "returns correct results for StartupProcedure parameter" {
            $result = Get-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure $startupProc
            $result.Schema | Should -Be 'dbo'
            $result.Name | Should -Be "StartUpProc$random"
        }

        It "returns null for incorrect StartupProcedure parameter" {
            $result = Get-DbaStartupProcedure -SqlInstance $global:instance2 -StartupProcedure 'Not.Here'
            $result | Should -BeNullOrEmpty
        }
    }
}
