param($ModuleName = 'dbatools')

Describe "Copy-DbaInstanceTrigger" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaInstanceTrigger
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have ServerTrigger as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServerTrigger -Type Object[]
        }
        It "Should have ExcludeServerTrigger as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeServerTrigger -Type Object[]
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

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

        It "should report success" {
            $results = Copy-DbaInstanceTrigger -Source $global:instance1 -Destination $global:instance2 -WarningAction SilentlyContinue
            $results.Status | Should -Be "Successful"
        }
    }
}
