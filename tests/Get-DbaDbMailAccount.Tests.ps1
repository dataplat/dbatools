#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMailAccount",
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
                "ExcludeAccount",
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
        $accountName = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_add_account_sp
            @account_name='$accountName',
            @description='Mail account for email alerts',
            @email_address='dbatoolssci@dbatools.io',
            @display_name ='dbatoolsci mail alerts',
            @mailserver_name='smtp.dbatools.io',
            @replyto_address='no-reply@dbatools.io';"
        $server.Query($mailAccountSettings)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created object.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_account_sp
            @account_name = '$accountName';"
        $server.Query($mailAccountSettings)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets DbMail Account" {
        BeforeAll {
            $results = Get-DbaDbMailAccount -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -eq $accountName
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

        It "Should have EmailAddress of 'dbatoolssci@dbatools.io' " {
            $results.EmailAddress | Should -Be "dbatoolssci@dbatools.io"
        }

        It "Should have ReplyToAddress of 'no-reply@dbatools.io' " {
            $results.ReplyToAddress | Should -Be "no-reply@dbatools.io"
        }

        It "Should have MailServer of '[smtp.dbatools.io]' " {
            $results.MailServers | Should -Be "[smtp.dbatools.io]"
        }
    }

    Context "Gets DbMail when using -Account" {
        BeforeAll {
            $results = Get-DbaDbMailAccount -SqlInstance $TestConfig.InstanceSingle -Account $accountName
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

        It "Should have EmailAddress of 'dbatoolssci@dbatools.io' " {
            $results.EmailAddress | Should -Be "dbatoolssci@dbatools.io"
        }

        It "Should have ReplyToAddress of 'no-reply@dbatools.io' " {
            $results.ReplyToAddress | Should -Be "no-reply@dbatools.io"
        }

        It "Should have MailServer of '[smtp.dbatools.io]' " {
            $results.MailServers | Should -Be "[smtp.dbatools.io]"
        }
    }

    Context "Gets no DbMail when using -ExcludeAccount" {
        It "Gets no results" {
            $results = Get-DbaDbMailAccount -SqlInstance $TestConfig.InstanceSingle -ExcludeAccount $accountName
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbMailAccount -SqlInstance $TestConfig.InstanceSingle -Account $accountName -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Mail.SqlMailAccount]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'ID',
                'Name',
                'DisplayName',
                'Description',
                'EmailAddress',
                'ReplyToAddress',
                'IsBusyAccount',
                'MailServers'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}