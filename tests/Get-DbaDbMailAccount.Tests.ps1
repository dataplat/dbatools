param($ModuleName = 'dbatools')

Describe "Get-DbaDbMailAccount" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMailAccount
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Account as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Account
        }
        It "Should have ExcludeAccount as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeAccount
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $accountname = "dbatoolsci_test_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $mailAccountSettings = @"
                EXEC msdb.dbo.sysmail_add_account_sp
                @account_name='$accountname',
                @description='Mail account for email alerts',
                @email_address='dbatoolssci@dbatools.io',
                @display_name ='dbatoolsci mail alerts',
                @mailserver_name='smtp.dbatools.io',
                @replyto_address='no-reply@dbatools.io';
"@
            $server.Query($mailAccountSettings)
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$accountname';"
            $server.Query($mailAccountSettings)
        }

        Context "Gets DbMail Account" {
            BeforeAll {
                $results = Get-DbaDbMailAccount -SqlInstance $global:instance2 | Where-Object { $_.Name -eq $accountname }
            }

            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }

            It "Should have Name of $accountname" {
                $results.Name | Should -Be $accountname
            }

            It "Should have Description of 'Mail account for email alerts'" {
                $results.Description | Should -Be 'Mail account for email alerts'
            }

            It "Should have EmailAddress of 'dbatoolssci@dbatools.io'" {
                $results.EmailAddress | Should -Be 'dbatoolssci@dbatools.io'
            }

            It "Should have ReplyToAddress of 'no-reply@dbatools.io'" {
                $results.ReplyToAddress | Should -Be 'no-reply@dbatools.io'
            }

            It "Should have MailServer of '[smtp.dbatools.io]'" {
                $results.MailServers | Should -Be '[smtp.dbatools.io]'
            }
        }

        Context "Gets DbMail when using -Account" {
            BeforeAll {
                $results = Get-DbaDbMailAccount -SqlInstance $global:instance2 -Account $accountname
            }

            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }

            It "Should have Name of $accountname" {
                $results.Name | Should -Be $accountname
            }

            It "Should have Description of 'Mail account for email alerts'" {
                $results.Description | Should -Be 'Mail account for email alerts'
            }

            It "Should have EmailAddress of 'dbatoolssci@dbatools.io'" {
                $results.EmailAddress | Should -Be 'dbatoolssci@dbatools.io'
            }

            It "Should have ReplyToAddress of 'no-reply@dbatools.io'" {
                $results.ReplyToAddress | Should -Be 'no-reply@dbatools.io'
            }

            It "Should have MailServer of '[smtp.dbatools.io]'" {
                $results.MailServers | Should -Be '[smtp.dbatools.io]'
            }
        }

        Context "Gets no DbMail when using -ExcludeAccount" {
            BeforeAll {
                $results = Get-DbaDbMailAccount -SqlInstance $global:instance2 -ExcludeAccount $accountname
            }

            It "Gets no results" {
                $results | Should -BeNullOrEmpty
            }
        }
    }
}
