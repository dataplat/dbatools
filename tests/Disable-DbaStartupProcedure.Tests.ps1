$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('WhatIf', 'Confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'StartupProcedure', 'InputObject', 'EnableException'
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
        $startupProcName = "StartUpProc$random"
        $startupProc = "dbo.$startupProcName"
        $dbname = 'master'

        $null = $server.Query("CREATE PROCEDURE $startupProc AS Select 1", $dbname)
        $null = $server.Query("EXEC sp_procoption '$startupProc', 'startup', 'on'", $dbname)
    }
    AfterAll {
        $null = $server.Query("DROP PROCEDURE $startupProc", $dbname)
    }

    Context "Validate returns correct output for disable" {
        $result = Disable-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure $startupProc -Confirm:$false

        It "returns correct results" {
            $result.Schema -eq "dbo" | Should Be $true
            $result.Name -eq "$startupProcName" | Should Be $true
            $result.Action -eq "Disable" | Should Be $true
            $result.Status | Should Be $true
            $result.Note -eq "Disable succeded" | Should Be $true
        }
    }

    Context "Validate returns correct output for already existing state" {
        $result = Disable-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure $startupProc -Confirm:$false

        It "returns correct results" {
            $result.Schema -eq "dbo" | Should Be $true
            $result.Name -eq "$startupProcName" | Should Be $true
            $result.Action -eq "Disable" | Should Be $true
            $result.Status | Should Be $false
            $result.Note -eq "Action Disable already performed" | Should Be $true
        }
    }

    Context "Validate returns correct results for piped input" {
        $null = Enable-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure $startupProc -Confirm:$false
        $result = Get-DbaStartupProcedure -SqlInstance $script:instance2 | Disable-DbaStartupProcedure -Confirm:$false

        It "returns correct results" {
            $result.Schema -eq "dbo" | Should Be $true
            $result.Name -eq "$startupProcName" | Should Be $true
            $result.Action -eq "Disable" | Should Be $true
            $result.Status | Should Be $true
            $result.Note -eq "Disable succeded" | Should Be $true
        }
    }
}