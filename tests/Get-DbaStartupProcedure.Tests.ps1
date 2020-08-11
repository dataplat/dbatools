$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'StartupProcedure', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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