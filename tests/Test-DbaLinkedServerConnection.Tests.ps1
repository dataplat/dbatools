param($ModuleName = 'dbatools')

Describe "Test-DbaLinkedServerConnection" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaLinkedServerConnection
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance1 -Database master
            $server.Query("EXEC master.dbo.sp_addlinkedserver @server = N'localhost', @srvproduct=N'SQL Server'")
        }
        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance1 -Database master
            $server.Query("EXEC master.dbo.sp_dropserver @server=N'localhost', @droplogins='droplogins'")
        }

        It "Function returns results" {
            $results = Test-DbaLinkedServerConnection -SqlInstance $script:instance1 | Where-Object LinkedServerName -eq 'localhost'
            $results | Should -Not -BeNullOrEmpty
        }

        It "Linked server name is localhost" {
            $results = Test-DbaLinkedServerConnection -SqlInstance $script:instance1 | Where-Object LinkedServerName -eq 'localhost'
            $results.LinkedServerName | Should -Be 'localhost'
        }

        It "Connectivity is true" {
            $results = Test-DbaLinkedServerConnection -SqlInstance $script:instance1 | Where-Object LinkedServerName -eq 'localhost'
            $results.Connectivity | Should -BeTrue
        }

        It "Piping from Get-DbaLinkedServer returns results" {
            $pipeResults = Get-DbaLinkedServer -SqlInstance $script:instance1 | Test-DbaLinkedServerConnection
            $pipeResults | Should -Not -BeNullOrEmpty
        }

        It "Piped linked server name is localhost" {
            $pipeResults = Get-DbaLinkedServer -SqlInstance $script:instance1 | Test-DbaLinkedServerConnection
            $pipeResults.LinkedServerName | Should -Be 'localhost'
        }

        It "Piped connectivity is true" {
            $pipeResults = Get-DbaLinkedServer -SqlInstance $script:instance1 | Test-DbaLinkedServerConnection
            $pipeResults.Connectivity | Should -BeTrue
        }
    }
}
