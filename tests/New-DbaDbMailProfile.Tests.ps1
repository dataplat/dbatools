param($ModuleName = 'dbatools')

Describe "New-DbaDbMailProfile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbMailProfile
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Profile as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Profile -Type System.String -Mandatory:$false
        }
        It "Should have Description as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Description -Type System.String -Mandatory:$false
        }
        It "Should have MailAccountName as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter MailAccountName -Type System.String -Mandatory:$false
        }
        It "Should have MailAccountPriority as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter MailAccountPriority -Type System.Int32 -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory parameter of type Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
