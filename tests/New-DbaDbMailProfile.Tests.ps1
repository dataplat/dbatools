param($ModuleName = 'dbatools')

Describe "New-DbaDbMailProfile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbMailProfile
        }
        
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Profile",
            "Description",
            "MailAccountName",
            "MailAccountPriority",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $profilename = "dbatoolsci_test_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $description = 'Mail account for email alerts'
            $mailaccountname = 'dbatoolssci@dbatools.io'
            $mailaccountpriority = 1

            $sql = "EXECUTE msdb.dbo.sysmail_add_account_sp
            @account_name = '$mailaccountname',
            @description = 'Mail account for administrative e-mail.',
            @email_address = 'dba@ad.local',
            @display_name = 'Automated Mailer',
            @mailserver_name = 'smtp.ad.local'"
            $server.Query($sql)
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = '$profilename';"
            $server.Query($mailAccountSettings)
            $regularaccountsettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$mailaccountname';"
            $server.Query($regularaccountsettings)
        }

        It "Sets DbMail Profile" {
            $splat = @{
                SqlInstance         = $global:instance2
                Profile             = $profilename
                Description         = $description
                MailAccountName     = $mailaccountname
                MailAccountPriority = $mailaccountpriority
            }
            $results = New-DbaDbMailProfile @splat

            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $profilename
            $results.Description | Should -Be $description
        }
    }
}
