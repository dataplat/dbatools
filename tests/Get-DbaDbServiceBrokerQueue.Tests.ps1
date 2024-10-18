param($ModuleName = 'dbatools')

Describe "Get-DbaDbServiceBrokerQueue" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbServiceBrokerQueue
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[]
        }
        It "Should have ExcludeSystemQueue as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemQueue -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $procname = ("dbatools_{0}" -f $(Get-Random))
            $server.Query("CREATE PROCEDURE $procname AS SELECT 1", 'tempdb')
            $queuename = ("dbatools_{0}" -f $(Get-Random))
            $server.Query("CREATE QUEUE $queuename WITH STATUS = ON , RETENTION = OFF , ACTIVATION (  STATUS = ON , PROCEDURE_NAME = $procname , MAX_QUEUE_READERS = 1 , EXECUTE AS OWNER  ), POISON_MESSAGE_HANDLING (STATUS = ON)", 'tempdb')
        }

        AfterAll {
            $null = $server.Query("DROP QUEUE $queuename", 'tempdb')
            $null = $server.Query("DROP PROCEDURE $procname", 'tempdb')
        }

        It "Gets the service broker queue" {
            $results = Get-DbaDbServiceBrokerQueue -SqlInstance $global:instance2 -Database tempdb -ExcludeSystemQueue
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $queuename
            $results.Schema | Should -Be "dbo"
        }
    }
}
