$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'MessageID', 'Severity', 'MessageText', 'Language', 'WithLog', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
    }
    AfterAll {
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70000) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70000, @lang = 'all'; END")
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70001) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70001, @lang = 'all'; END")
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70002) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70002, @lang = 'all'; END")
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70003) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70003, @lang = 'all'; END")
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70004) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70004, @lang = 'all'; END")
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70005) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70005, @lang = 'all'; END")
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70006) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70006, @lang = 'all'; END")
        $server2.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70006) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70006, @lang = 'all'; END")
    }

    Context "Validate params" {

        It "Message ID" {
            { $results = New-DbaCustomError -SqlInstance $server -MessageID 1 -Severity 1 -MessageText "test 1" -Language English } | Should -Throw
            { $results = New-DbaCustomError -SqlInstance $server -MessageID 2147483648 -Severity 1 -MessageText "test 1" -Language English } | Should -Throw

            $results = New-DbaCustomError -SqlInstance $server -MessageID 70000 -Severity 16 -MessageText "test_70000"
            $results.Count | Should -Be 1
            $results.ID | Should -Be 70000
        }

        It "Severity" {
            { $results = New-DbaCustomError -SqlInstance $server -MessageID 70001 -Severity 0 -MessageText "test 1" -Language English } | Should -Throw
            { $results = New-DbaCustomError -SqlInstance $server -MessageID 70001 -Severity 26 -MessageText "test 1" -Language English } | Should -Throw
            $results = New-DbaCustomError -SqlInstance $server -MessageID 70001 -Severity 16 -MessageText "test_70001"
            $results.Count | Should -Be 1
            $results.Severity | Should -Be 16
        }

        It "MessageText" {
            { $results = New-DbaCustomError -SqlInstance $server -MessageID 70001 -Severity 1 -MessageText "test message that has a string length greater than 255 characters. test message that has a string length greater than 255 characters. test message that has a string length greater than 255 characters. test message that has a string length greater than 255 characters" -Language English } | Should -Throw

            $results = New-DbaCustomError -SqlInstance $server -MessageID 70002 -Severity 1 -MessageText "test_70002"
            $results.Count | Should -Be 1
            $results.Text | Should -Be "test_70002"
        }

        It "Language" {
            $results = New-DbaCustomError -SqlInstance $server -MessageID 70001 -Severity 1 -MessageText "test" -Language "InvalidLanguage" -WarningAction SilentlyContinue -WarningVariable WarnVar
            $WarnVar | Should -Match "does not have the InvalidLanguage installed"
            $results | Should -BeNullOrEmpty

            $results = New-DbaCustomError -SqlInstance $server -MessageID 70003 -Severity 1 -MessageText "test_70003" -Language "English"
            $results.Count | Should -Be 1
            $results.Language | Should -Match "English"
            $results.Text | Should -Be "test_70003"
            $results.ID | Should -Be 70003
            $results.Severity | Should -Be 1

            # add other languages available now that the english message is added
            $languages = $server.Query("SELECT alias FROM sys.syslanguages WHERE alias NOT LIKE '%English%'")

            foreach ($lang in $languages) {
                $languageName = $lang.alias
                $results = New-DbaCustomError -SqlInstance $server -MessageID 70003 -Severity 1 -MessageText "test_70003_$languageName" -Language "$languageName"
                $results.Count | Should -Be 1
                $results.Language | Should -Match "$languageName"
                $results.Text | Should -Be "test_70003_$languageName"
                $results.ID | Should -Be 70003
                $results.Severity | Should -Be 1
            }
        }

        It "WithLog" {
            $results = New-DbaCustomError -SqlInstance $server -MessageID 70005 -Severity 25 -MessageText "test_70005" -WithLog
            $results.Count | Should -Be 1
            $results.Text | Should -Be "test_70005"
            $results.Severity | Should -Be 25
            $results.ID | Should -Be 70005
            $results.IsLogged | Should -Be $true
        }
    }

    Context "Supports multiple server inputs" {

        It "Add messages to preconnected servers" {
            $results = ([DbaInstanceParameter[]]$server, $server2 | New-DbaCustomError -MessageID 70006 -Severity 20 -MessageText "test_70006")
            $results.Count | Should -Be 2
            $results[0].Text | Should -Be "test_70006"
            $results[1].Text | Should -Be "test_70006"
            $results[0].Severity | Should -Be 20
            $results[1].Severity | Should -Be 20
            $results[0].ID | Should -Be 70006
            $results[1].ID | Should -Be 70006
        }
    }
}