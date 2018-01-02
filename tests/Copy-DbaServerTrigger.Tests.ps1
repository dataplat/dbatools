$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

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
            }
            catch {
                # dont care
            }
        }

        $results = Copy-DbaServerTrigger -Source $script:instance1 -Destination $script:instance2 -WarningVariable warn -WarningAction SilentlyContinue # -ServerTrigger $triggername

        It "should report success" {
            $results.Status | Should Be "Successful"
        }

        # same properties need to be added
    }
}
