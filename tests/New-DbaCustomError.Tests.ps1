#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaCustomError",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "MessageID",
                "Severity",
                "MessageText",
                "Language",
                "WithLog",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70000) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70000, @lang = 'all'; END")
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70001) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70001, @lang = 'all'; END")
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70002) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70002, @lang = 'all'; END")
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70003) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70003, @lang = 'all'; END")
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70004) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70004, @lang = 'all'; END")
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70005) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70005, @lang = 'all'; END")
        $server.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70006) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70006, @lang = 'all'; END")
        $server2.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70006) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70006, @lang = 'all'; END")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
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