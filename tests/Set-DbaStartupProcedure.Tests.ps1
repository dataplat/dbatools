$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('WhatIf', 'Confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'StartupProcedure', 'Disable', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }

    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe "$commandname Integration Test" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $random = Get-Random
        $startupProc = "dbo.StartUpProc$random"
        $dbname = 'master'

        $null = $server.Query("CREATE PROCEDURE $startupProc AS Select 1", $dbname)
    }
    AfterAll {
        $null = $server.Query("DROP PROCEDURE $startupProc", $dbname)
    }

    Context "Validate returns correct output for enable" {
        $result = Set-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure $startupProc -Confirm:$false

        It "returns correct results" {
            $result.StartupProcedure -eq "$startupProc" | Should Be $true
            $result.Action -eq "Enable" | Should Be $true
            $result.Status | Should Be $true
            $result.Note -eq "Enable succeded" | Should Be $true
        }
    }

    Context "Validate returns correct output for already existing state" {
        $result = Set-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure $startupProc -Confirm:$false

        It "returns correct results" {
            $result.StartupProcedure -eq "$startupProc" | Should Be $true
            $result.Action -eq "Enable" | Should Be $true
            $result.Status | Should Be $true
            $result.Note -eq "Requested status already set." | Should Be $true
        }
    }

    Context "Validate returns correct output for disable" {
        $result = Set-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure $startupProc -Disable -Confirm:$false

        It "returns correct results" {
            $result.StartupProcedure -eq "$startupProc" | Should Be $true
            $result.Action -eq "Disable" | Should Be $true
            $result.Status | Should Be $true
            $result.Note -eq "Disable succeded" | Should Be $true
        }
    }

    Context "Validate returns correct output for missing procedures" {
        $result = Set-DbaStartupProcedure -SqlInstance $script:instance2 -StartupProcedure "Unknown.NotHere" -Confirm:$false

        It "returns correct results" {
            $result.StartupProcedure -eq "Unknown.NotHere" | Should Be $true
            $result.Action -eq "Enable" | Should Be $true
            $result.Status | Should Be $false
            $result.Note -eq "Requested procedure does not exist" | Should Be $true
        }
    }
}