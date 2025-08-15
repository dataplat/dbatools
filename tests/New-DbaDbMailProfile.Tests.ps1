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
        $mailaccountpriority = 1

        $sql = "EXECUTE msdb.dbo.sysmail_add_account_sp
        @account_name = '$mailaccountname',
        @description = 'Mail account for administrative e-mail.',
        @email_address = 'dba@ad.local',
        @display_name = 'Automated Mailer',
        @mailserver_name = 'smtp.ad.local'"
        $server.Query($sql)

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

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
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
}