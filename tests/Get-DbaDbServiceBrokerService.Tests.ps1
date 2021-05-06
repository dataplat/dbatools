$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException', 'Database', 'ExcludeDatabase', 'ExcludeSystemService'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
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
        $servicename = ("dbatools_{0}" -f $(Get-Random))
        $server.Query("CREATE SERVICE $servicename ON QUEUE $queuename ([DEFAULT])", 'tempdb')
    }
    AfterAll {
        $null = $server.Query("DROP SERVICE $servicename", 'tempdb')
        $null = $server.Query("DROP QUEUE $queuename", 'tempdb')
        $null = $server.Query("DROP PROCEDURE $procname", 'tempdb')
    }

    Context "Gets the service broker service" {
        $results = Get-DbaDbServiceBrokerService -SqlInstance $script:instance2 -database tempdb -ExcludeSystemService:$true
        It "Gets results" {
            $results | Should Not Be $Null
        }
        It "Should have a name of $servicename" {
            $results.name | Should Be "$servicename"
        }
        It "Should have an owner of dbo" {
            $results.owner | Should Be "dbo"
        }
        It "Should have a queuename of $queuename" {
            $results.QueueName | Should be "$QueueName"
        }
    }
}