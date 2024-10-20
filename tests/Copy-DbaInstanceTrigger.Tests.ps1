param($ModuleName = 'dbatools')

Describe "Copy-DbaInstanceTrigger" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaInstanceTrigger
        }
        $paramList = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'ServerTrigger',
            'ExcludeServerTrigger',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $triggername = "dbatoolsci-trigger"
            $sql = "CREATE TRIGGER [$triggername] -- Trigger name
                    ON ALL SERVER FOR LOGON -- Tells you it's a logon trigger
                    AS
                    PRINT 'hello'"
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $server.Query($sql)
        }
        AfterAll {
            $server.Query("DROP TRIGGER [$triggername] ON ALL SERVER")

            try {
                $server1 = Connect-DbaInstance -SqlInstance $global:instance2
                $server1.Query("DROP TRIGGER [$triggername] ON ALL SERVER")
            } catch {
                # don't care
            }
        }

        It "should copy the trigger successfully" {
            $results = Copy-DbaInstanceTrigger -Source $global:instance1 -Destination $global:instance2 -WarningAction SilentlyContinue
            $results.Status | Should -Be "Successful"
        }

        # Additional tests can be added here to check other properties of the copied trigger
    }
}
