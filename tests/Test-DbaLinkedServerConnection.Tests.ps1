$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        Get-DbaProcess -SqlInstance $script:instance1 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance1 -Database master
        $server.Query("EXEC master.dbo.sp_addlinkedserver @server = N'localhost', @srvproduct=N'SQL Server'")
    }
    AfterAll {
        Get-DbaProcess -SqlInstance $script:instance1 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance1 -Database master
        $server.Query("EXEC master.dbo.sp_dropserver @server=N'localhost', @droplogins='droplogins'")
    }
    Context "Function works" {
        $results = Test-DbaLinkedServerConnection -SqlInstance $script:instance1 | Where-Object LinkedServerName -eq 'localhost'
        It "function returns results" {
            $results | Should Not BeNullOrEmpty
        }
        It "linked server name is localhost" {
            $results.LinkedServerName | Should Be 'localhost'
        }
        It "connectivity is true" {
            $results.Connectivity | Should BeTrue
        }
    }

    Context "Piping to function works" {
        $pipeResults = Get-DbaLinkedServer -SqlInstance $script:instance1 | Test-DbaLinkedServerConnection
        It "piping from Get-DbaLinkedServerConnection returns results" {
            $pipeResults | Should Not BeNullOrEmpty
        }
        It "linked server name is localhost" {
            $pipeResults.LinkedServerName | Should Be 'localhost'
        }
        It "connectivity is true" {
            $pipeResults.Connectivity | Should BeTrue
        }
    }
}