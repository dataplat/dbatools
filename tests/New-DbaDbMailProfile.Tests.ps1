#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbMailProfile",
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
                "Profile",
                "Description",
                "MailAccountName",
                "MailAccountPriority",
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

        $profilename = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $description = "Mail account for email alerts"
        $mailaccountname = "dbatoolssci@dbatools.io"
        $mailaccountname2 = "dbatoolssci2@dbatools.io"
        $mailaccountpriority = 1

        $sql = "EXECUTE msdb.dbo.sysmail_add_account_sp
        @account_name = '$mailaccountname',
        @description = 'Mail account for administrative e-mail.',
        @email_address = 'dba@ad.local',
        @display_name = 'Automated Mailer',
        @mailserver_name = 'smtp.ad.local'"
        $server.Query($sql)

        $sql2 = "EXECUTE msdb.dbo.sysmail_add_account_sp
        @account_name = '$mailaccountname2',
        @description = 'Second mail account for administrative e-mail.',
        @email_address = 'dba2@ad.local',
        @display_name = 'Automated Mailer 2',
        @mailserver_name = 'smtp.ad.local'"
        $server.Query($sql2)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = '$profilename';"
        $server.query($mailAccountSettings)
        $regularaccountsettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$mailaccountname';"
        $server.query($regularaccountsettings)
        $regularaccountsettings2 = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$mailaccountname2';"
        $server.query($regularaccountsettings2)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Sets DbMail Profile" {
        BeforeAll {
            $splatProfile = @{
                SqlInstance         = $TestConfig.instance2
                Profile             = $profilename
                Description         = $description
                MailAccountName     = $mailaccountname
                MailAccountPriority = $mailaccountpriority
            }
            $results = New-DbaDbMailProfile @splatProfile
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have Name of $profilename" {
            $results.name | Should -Be $profilename
        }
        It "Should have Description of $description " {
            $results.description | Should -Be $description
        }
    }

    Context "Adds multiple accounts to the same profile" {
        It "Should allow adding a second account to existing profile without error" {
            $splatProfile2 = @{
                SqlInstance         = $TestConfig.instance2
                Profile             = $profilename
                MailAccountName     = $mailaccountname2
                MailAccountPriority = 2
            }
            { New-DbaDbMailProfile @splatProfile2 } | Should -Not -Throw
        }

        It "Should have both accounts associated with the profile" {
            $profile = Get-DbaDbMailProfile -SqlInstance $TestConfig.instance2 -Profile $profilename
            $accounts = $profile.EnumAccounts()
            $accounts.Count | Should -Be 2
        }

        It "Should fail with clear message when trying to create duplicate profile without MailAccountName" {
            $splatDuplicate = @{
                SqlInstance = $TestConfig.instance2
                Profile     = $profilename
                Description = "Duplicate attempt"
            }
            $warningMessage = New-DbaDbMailProfile @splatDuplicate 3>&1
            $warningMessage | Should -Match "Profile .* already exists"
        }
    }
}