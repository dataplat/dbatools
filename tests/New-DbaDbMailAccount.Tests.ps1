param($ModuleName = 'dbatools')

Describe "New-DbaDbMailAccount" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbMailAccount
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
        It "Should have DisplayName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter DisplayName
        }
        It "Should have Description as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Description
        }
        It "Should have EmailAddress as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter EmailAddress
        }
        It "Should have ReplyToAddress as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ReplyToAddress
        }
        It "Should have MailServer as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter MailServer
        }
        It "Should have Force as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
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
            $accountName = "dbatoolsci_test_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $description = 'Mail account for email alerts'
            $email_address = 'dbatoolssci@dbatools.net'
            $display_name = 'dbatoolsci mail alerts'
            $mailserver_name = 'smtp.dbatools.io'
            $replyto_address = 'no-reply@dbatools.net'

            if ((Get-DbaSpConfigure -SqlInstance $server -Name 'Database Mail XPs').RunningValue -ne 1) {
                Set-DbaSpConfigure -SqlInstance $server -Name 'Database Mail XPs' -Value 1
            }
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$accountName';"
            $server.Query($mailAccountSettings)
        }

        It "Creates a new DbMail Account" {
            $splat = @{
                SqlInstance    = $global:instance2
                Account        = $accountName
                Description    = $description
                EmailAddress   = $email_address
                DisplayName    = $display_name
                ReplyToAddress = $replyto_address
            }
            $results = New-DbaDbMailAccount @splat

            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $accountName
            $results.Description | Should -Be 'Mail account for email alerts'
            $results.EmailAddress | Should -Be $email_address
            $results.ReplyToAddress | Should -Be 'no-reply@dbatools.net'
        }

        It "Gets the created DbMail Account" {
            $results = Get-DbaDbMailAccount -SqlInstance $server -Account $accountName

            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $accountName
            $results.Description | Should -Be 'Mail account for email alerts'
            $results.EmailAddress | Should -Be 'dbatoolssci@dbatools.net'
            $results.ReplyToAddress | Should -Be 'no-reply@dbatools.net'
        }

        It "Excludes the created DbMail Account when using -ExcludeAccount" {
            $results = Get-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountName
            $results | Should -BeNullOrEmpty
        }
    }
}
