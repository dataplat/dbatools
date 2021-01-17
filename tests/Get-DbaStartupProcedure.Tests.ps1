$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'StartupProcedure', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$commandname Integration Test" -Tag "IntegrationTests" {
    BeforeAll {
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

    Context "Validate returns correct output" {
        $result = Get-DbaStartupProcedure -SqlInstance $script:instance2
        It "returns correct results" {
            $result.Schema -eq 'dbo' | Should Be $true
            $result.Name -eq "StartUpProc$random" | Should Be $true
        }
    }

    Context "Validate returns correct output for StartupProcedure parameter " {
        $result = Get-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure $startupProc
        It "returns correct results" {
            $result.Schema -eq 'dbo' | Should Be $true
            $result.Name -eq "StartUpProc$random" | Should Be $true
        }
    }

    Context "Validate returns correct output for incorrect StartupProcedure parameter " {
        $result = Get-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure 'Not.Here'
        It "returns correct results" {
            $null -eq $result | Should Be $true
        }
    }
}