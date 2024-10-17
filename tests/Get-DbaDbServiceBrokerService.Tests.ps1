param($ModuleName = 'dbatools')

Describe "Get-DbaDbServiceBrokerService" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbServiceBrokerService
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have ExcludeSystemService as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemService -Type SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command usage" {
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

        It "Gets the service broker service" {
            $results = Get-DbaDbServiceBrokerService -SqlInstance $script:instance2 -Database tempdb -ExcludeSystemService
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $servicename
            $results.Owner | Should -Be "dbo"
            $results.QueueName | Should -Be $queuename
        }
    }
}
