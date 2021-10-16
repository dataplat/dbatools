$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException', 'Database', 'ExcludeDatabase', 'ExcludeSystemQueue'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $procname = ("dbatools_{0}" -f $(Get-Random))
        $server.Query("CREATE PROCEDURE $procname AS SELECT 1", 'tempdb')
        $queuename = ("dbatools_{0}" -f $(Get-Random))
        $server.Query("CREATE QUEUE $queuename WITH STATUS = ON , RETENTION = OFF , ACTIVATION (  STATUS = ON , PROCEDURE_NAME = $procname , MAX_QUEUE_READERS = 1 , EXECUTE AS OWNER  ), POISON_MESSAGE_HANDLING (STATUS = ON)", 'tempdb')
    }
    AfterAll {
        $null = $server.Query("DROP QUEUE $queuename", 'tempdb')
        $null = $server.Query("DROP PROCEDURE $procname", 'tempdb')
    }

    Context "Gets the service broker queue" {
        $results = Get-DbaDbServiceBrokerQueue -SqlInstance $script:instance2 -database tempdb -ExcludeSystemQueue:$true
        It "Gets results" {
            $results | Should Not Be $Null
        }
        It "Should have a name of $queuename" {
            $results.name | Should Be "$queuename"
        }
        It "Should have an schema of dbo" {
            $results.schema | Should Be "dbo"
        }
    }
}