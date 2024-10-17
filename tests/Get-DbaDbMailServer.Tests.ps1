param($ModuleName = 'dbatools')

Describe "Get-DbaDbMailServer" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMailServer
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Server as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Server -Type String[] -Mandatory:$false
        }
        It "Should have Account as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Account -Type String[] -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type SqlMail[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type SqlMail[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $accountname = "dbatoolsci_test_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $mailAccountSettings = "EXEC msdb.dbo.sysmail_add_account_sp
                @account_name='$accountname',
                @description='Mail account for email alerts',
                @email_address='dbatoolssci@dbatools.io',
                @display_name ='dbatoolsci mail alerts',
                @mailserver_name='smtp.dbatools.io',
                @replyto_address='no-reply@dbatools.io';"
            $server.Query($mailAccountSettings)
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_account_sp
                @account_name = '$accountname';"
            $server.Query($mailAccountSettings)
        }

        Context "Gets DbMailServer" {
            BeforeAll {
                $results = Get-DbaDbMailServer -SqlInstance $global:instance2 | Where-Object {$_.Account -eq $accountname}
            }

            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should have Account of $accountname" {
                $results.Account | Should -Be $accountname
            }
            It "Should have Name of 'smtp.dbatools.io'" {
                $results.Name | Should -Be 'smtp.dbatools.io'
            }
            It "Should have Port on 25" {
                $results.Port | Should -Be 25
            }
            It "Should have SSL Disabled" {
                $results.EnableSSL | Should -BeFalse
            }
            It "Should have ServerType of 'SMTP'" {
                $results.ServerType | Should -Be 'SMTP'
            }
        }

        Context "Gets DbMailServer using -Server" {
            BeforeAll {
                $results = Get-DbaDbMailServer -SqlInstance $global:instance2 -Server 'smtp.dbatools.io'
            }

            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
        }

        Context "Gets DbMailServer using -Account" {
            BeforeAll {
                $results = Get-DbaDbMailServer -SqlInstance $global:instance2 -Account $accountname
            }

            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
        }
    }
}
