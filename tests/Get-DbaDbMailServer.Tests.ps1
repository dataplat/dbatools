#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMailServer",
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
                "Server",
                "Account",
                "InputObject",
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

        # Set variables. They are available in all the It blocks.
        $mailAccountName = "dbatoolsci_test_$(Get-Random)"

        # Create the mail account for testing
        $primaryServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_add_account_sp
            @account_name='$mailAccountName',
            @description='Mail account for email alerts',
            @email_address='dbatoolssci@dbatools.io',
            @display_name ='dbatoolsci mail alerts',
            @mailserver_name='smtp.dbatools.io',
            @replyto_address='no-reply@dbatools.io';"
        $primaryServer.Query($mailAccountSettings)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $cleanupServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_account_sp
            @account_name = '$mailAccountName';"
        $cleanupServer.Query($mailAccountSettings)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets DbMailServer" {
        BeforeAll {
            $mailServerResults = Get-DbaDbMailServer -SqlInstance $TestConfig.instance2 | Where-Object Account -eq $mailAccountName
        }

        It "Gets results" {
            $mailServerResults | Should -Not -BeNullOrEmpty
        }

        It "Should have Account of $mailAccountName" {
            $mailServerResults.Account | Should -Be $mailAccountName
        }

        It "Should have Name of 'smtp.dbatools.io'" {
            $mailServerResults.Name | Should -Be "smtp.dbatools.io"
        }

        It "Should have Port on 25" {
            $mailServerResults.Port | Should -Be 25
        }

        It "Should have SSL Disabled" {
            $mailServerResults.EnableSSL | Should -Be $false
        }

        It "Should have ServerType of 'SMTP'" {
            $mailServerResults.ServerType | Should -Be "SMTP"
        }
    }

    Context "Gets DbMailServer using -Server" {
        BeforeAll {
            $serverFilterResults = Get-DbaDbMailServer -SqlInstance $TestConfig.instance2 -Server "smtp.dbatools.io"
        }

        It "Gets results" {
            $serverFilterResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "Gets DbMailServer using -Account" {
        BeforeAll {
            $accountFilterResults = Get-DbaDbMailServer -SqlInstance $TestConfig.instance2 -Account $mailAccountName
        }

        It "Gets results" {
            $accountFilterResults | Should -Not -BeNullOrEmpty
        }
    }
}