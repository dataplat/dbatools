$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'ServerTrigger', 'ExcludeServerTrigger', 'Force', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $triggername = "dbatoolsci-trigger"
            $sql = "CREATE TRIGGER [$triggername] -- Trigger name
                    ON ALL SERVER FOR LOGON -- Tells you it's a logon trigger
                    AS
                    PRINT 'hello'"
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $server.Query($sql)
        }
        AfterAll {
            $server.Query("DROP TRIGGER [$triggername] ON ALL SERVER")

            try {
                $server1 = Connect-DbaInstance -SqlInstance $script:instance2
                $server1.Query("DROP TRIGGER [$triggername] ON ALL SERVER")
            } catch {
                # don't care
            }
        }

        $results = Copy-DbaInstanceTrigger -Source $script:instance1 -Destination $script:instance2 -WarningVariable warn -WarningAction SilentlyContinue # -ServerTrigger $triggername

        It "should report success" {
            $results.Status | Should Be "Successful"
        }
        # same properties need to be added
    }
}