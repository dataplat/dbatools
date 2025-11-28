#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbMailAccount",
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
                "Account",
                "DisplayName",
                "Description",
                "EmailAddress",
                "ReplyToAddress",
                "MailServer",
                "Port",
                "EnableSSL",
                "UseDefaultCredentials",
                "UserName",
                "Password",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $accountName = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $description = "Mail account for email alerts"
        $email_address = "dbatoolssci@dbatools.net"
        $display_name = "dbatoolsci mail alerts"
        $mailserver_name = "smtp.dbatools.io"
        $replyto_address = "no-reply@dbatools.net"

        if ( (Get-DbaSpConfigure -SqlInstance $server -Name "Database Mail XPs").RunningValue -ne 1 ) {
            Set-DbaSpConfigure -SqlInstance $server -Name "Database Mail XPs" -Value 1
        }
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$accountName';"
        $server.query($mailAccountSettings)
    }

    Context "Gets DbMail Account" {
        BeforeAll {
            $splatMailAccount = @{
                SqlInstance    = $TestConfig.instance2
                Account        = $accountName
                Description    = $description
                EmailAddress   = $email_address
                DisplayName    = $display_name
                ReplyToAddress = $replyto_address
                # MailServer is not set, because we don't want to configure the mail server on the instance.
                # MailServer     = $mailserver_name
            }
            $results = New-DbaDbMailAccount @splatMailAccount
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have Name of $accountName" {
            $results.Name | Should -Be $accountName
        }
        It "Should have Description of 'Mail account for email alerts' " {
            $results.Description | Should -Be "Mail account for email alerts"
        }
        # TODO: If we set the variables then we should use them, don't we?
        It "Should have EmailAddress of '$email_address' " {
            $results.EmailAddress | Should -Be $email_address
        }
        It "Should have ReplyToAddress of 'no-reply@dbatools.net' " {
            $results.ReplyToAddress | Should -Be "no-reply@dbatools.net"
        }
        # Skipped, because we have not set the MailServer, because we don't want to configure the mail server on the instance.
        It "Should have MailServer of '[smtp.dbatools.io]' " -Skip {
            $results.MailServers | Should -Be "[smtp.dbatools.io]"
        }
    }
    Context "Gets DbMail when using -Account" {
        BeforeAll {
            $results = Get-DbaDbMailAccount -SqlInstance $server -Account $accountName
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have Name of $accountName" {
            $results.name | Should -Be $accountName
        }
        It "Should have Description of 'Mail account for email alerts' " {
            $results.description | Should -Be "Mail account for email alerts"
        }
        It "Should have EmailAddress of 'dbatoolssci@dbatools.net' " {
            $results.EmailAddress | Should -Be "dbatoolssci@dbatools.net"
        }
        It "Should have ReplyToAddress of 'no-reply@dbatools.net' " {
            $results.ReplyToAddress | Should -Be "no-reply@dbatools.net"
        }
        # Skipped, because we have not set the MailServer, because we don't want to configure the mail server on the instance.
        It "Should have MailServer of '[smtp.dbatools.io]' " -Skip {
            $results.MailServers | Should -Be "[smtp.dbatools.io]"
        }
    }
    Context "Gets no DbMail when using -ExcludeAccount" {
        It "Gets no results" {
            $results = Get-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountName
            $results | Should -BeNullOrEmpty
        }
    }
}