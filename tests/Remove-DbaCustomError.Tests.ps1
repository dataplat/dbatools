#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaCustomError",
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
                "Language",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $serverPrimary = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $serverSecondary = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        $null = New-DbaCustomError -SqlInstance $serverPrimary -MessageID 70000 -Severity 1 -MessageText "test_70000"
        $null = New-DbaCustomError -SqlInstance $serverPrimary, $serverSecondary -MessageID 70001 -Severity 1 -MessageText "test_70001"
        $null = New-DbaCustomError -SqlInstance $serverPrimary, $serverSecondary -MessageID 70002 -Severity 1 -MessageText "test_70002"
        $null = New-DbaCustomError -SqlInstance $serverPrimary -MessageID 70003 -Severity 1 -MessageText "test_70003" -Language "English"
        $null = New-DbaCustomError -SqlInstance $serverPrimary -MessageID 70005 -Severity 5 -MessageText "test_70005" -Language "English"

        # add other languages available now that the english message is added
        $availableLanguages = $serverPrimary.Query("SELECT alias FROM sys.syslanguages WHERE alias NOT LIKE '%English%'")

        foreach ($languageEntry in $availableLanguages) {
            $languageName = $languageEntry.alias
            $null = New-DbaCustomError -SqlInstance $serverPrimary -MessageID 70003 -Severity 1 -MessageText "test_70003_$languageName" -Language "$languageName"
            $null = New-DbaCustomError -SqlInstance $serverPrimary -MessageID 70005 -Severity 5 -MessageText "test_70005_$languageName" -Language "$languageName"
        }

        $null = New-DbaCustomError -SqlInstance $serverPrimary -MessageID 70004 -Severity 1 -MessageText "test_70004" -Language "English"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $serverPrimary.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70000) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70000, @lang = 'all'; END")
        $serverPrimary.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70001) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70001, @lang = 'all'; END")
        $serverPrimary.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70002) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70002, @lang = 'all'; END")
        $serverPrimary.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70003) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70003, @lang = 'all'; END")
        $serverPrimary.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70004) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70004, @lang = 'all'; END")
        $serverPrimary.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70005) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70005, @lang = 'all'; END")
        $serverSecondary.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70001) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70001, @lang = 'all'; END")
        $serverSecondary.Query("IF EXISTS (SELECT 1 FROM master.sys.messages WHERE message_id = 70002) BEGIN EXEC msdb.dbo.sp_dropmessage @msgnum = 70002, @lang = 'all'; END")

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Parameter validation tests" {
        It "Message ID validation" {
            { $testResults = Remove-DbaCustomError -SqlInstance $serverPrimary -MessageID 1 -Language "English" } | Should -Throw
            { $testResults = Remove-DbaCustomError -SqlInstance $serverPrimary -MessageID 2147483648 -Language "English" } | Should -Throw

            $testResults = Remove-DbaCustomError -SqlInstance $serverPrimary -MessageID 70000
            ($serverPrimary.UserDefinedMessages | Where-Object ID -eq 70000).Count | Should -Be 0
        }

        It "Language validation" {
            $testResults = Remove-DbaCustomError -SqlInstance $serverPrimary -MessageID 70003 -Language "InvalidLanguage" -WarningAction SilentlyContinue
            $testResults | Should -BeNullOrEmpty

            $testResults = Remove-DbaCustomError -SqlInstance $serverPrimary -MessageID 70003 -Language "French"
            ($serverPrimary.UserDefinedMessages | Where-Object { $PSItem.ID -eq 70003 -and $PSItem.Language -eq "French" }).Count | Should -Be 0

            $testResults = Remove-DbaCustomError -SqlInstance $serverPrimary -MessageID 70003 -Language "All"
            ($serverPrimary.UserDefinedMessages | Where-Object ID -eq 70003).Count | Should -Be 0 # SMO does a cascade delete of all messages by related ID in this scenario, so the resulting count is 1.

            $testResults = Remove-DbaCustomError -SqlInstance $serverPrimary -MessageID 70004 -Language "English"
            ($serverPrimary.UserDefinedMessages | Where-Object ID -eq 70004).Count | Should -Be 0

            $testResults = Remove-DbaCustomError -SqlInstance $serverPrimary -MessageID 70005
            ($serverPrimary.UserDefinedMessages | Where-Object ID -eq 70005).Count | Should -Be 0
        }
    }

    Context "Multiple server input support" {
        It "Supports preconnected servers" {
            $testResults = ([DbaInstanceParameter[]]$serverPrimary, $serverSecondary | Remove-DbaCustomError -MessageID 70001)
            ($serverPrimary.UserDefinedMessages | Where-Object ID -eq 70001).Count | Should -Be 0
            ($serverSecondary.UserDefinedMessages | Where-Object ID -eq 70001).Count | Should -Be 0
        }

        It "Supports multiple servers via SqlInstance parameter" {
            $testResults = Remove-DbaCustomError -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -MessageID 70002
            # even the SMO server.Refresh() doesn't pick up the changes to the user defined messages
            $serverPrimaryReconnected = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $serverSecondaryReconnected = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            ($serverPrimaryReconnected.UserDefinedMessages | Where-Object ID -eq 70002).Count | Should -Be 0
            ($serverSecondaryReconnected.UserDefinedMessages | Where-Object ID -eq 70002).Count | Should -Be 0
        }
    }

    Context "Update simulation tests" {
        It "Should simulate an update using existing commands" {
            $testResults = New-DbaCustomError -SqlInstance $serverPrimary -MessageID 70000 -Severity 1 -MessageText "test_70000"
            $testResults.IsLogged | Should -Be $false
            $testResults.Text | Should -Be "test_70000"

            $originalMessage = $serverPrimary.UserDefinedMessages | Where-Object ID -eq 70000

            $messageID = $originalMessage.ID
            $messageSeverity = $originalMessage.Severity
            $updatedText = "updated text"
            $messageLanguage = $originalMessage.Language

            $removedMessage = Remove-DbaCustomError -SqlInstance $serverPrimary -MessageID 70000

            $updatedMessage = New-DbaCustomError -SqlInstance $serverPrimary -MessageID $messageID -Severity $messageSeverity -MessageText $updatedText -Language $messageLanguage -WithLog
            $updatedMessage.IsLogged | Should -Be $true
            $updatedMessage.ID | Should -Be 70000
            $updatedMessage.Text | Should -Be "updated text"
        }
    }
}