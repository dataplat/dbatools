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
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = '$profilename';"
        $server.query($mailAccountSettings)
        $regularaccountsettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$mailaccountname';"
        $server.query($regularaccountsettings)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Sets DbMail Profile" {
        BeforeAll {
            $splatProfile = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Profile             = $profilename
                Description         = $description
                MailAccountName     = $mailaccountname
                MailAccountPriority = $mailaccountpriority
            }
            $results = New-DbaDbMailProfile @splatProfile -OutVariable "global:dbatoolsciOutput"
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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Mail.MailProfile]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Id",
                "Name",
                "Description",
                "IsBusyProfile"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Mail\.MailProfile"
        }
    }
}