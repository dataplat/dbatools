param($ModuleName = 'dbatools')

Describe "New-DbaDbMailProfile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbMailProfile
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Profile as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Profile -Type String -Not -Mandatory
        }
        It "Should have Description as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Description -Type String -Not -Mandatory
        }
        It "Should have MailAccountName as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter MailAccountName -Type String -Not -Mandatory
        }
        It "Should have MailAccountPriority as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter MailAccountPriority -Type Int32 -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory parameter of type SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $profilename = "dbatoolsci_test_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
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
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = '$profilename';"
            $server.Query($mailAccountSettings)
            $regularaccountsettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$mailaccountname';"
            $server.Query($regularaccountsettings)
        }

        It "Sets DbMail Profile" {
            $splat = @{
                SqlInstance         = $script:instance2
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
