param($ModuleName = 'dbatools')

Describe "Copy-DbaDbMail" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaDbMail
        }
        $parms = @(
            'Source',
            'Destination',
            'Type',
            'SourceSqlCredential',
            'DestinationSqlCredential',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $servers = Connect-DbaInstance -SqlInstance $global:instance2, $global:instance3
            foreach ($s in $servers) {
                if ( (Get-DbaSpConfigure -SqlInstance $s -Name 'Database Mail XPs').RunningValue -ne 1 ) {
                    Set-DbaSpConfigure -SqlInstance $s -Name 'Database Mail XPs' -Value 1
                }
            }

            $accountName = "dbatoolsci_test_$(Get-Random)"
            $account_display_name = 'dbatoolsci mail alerts'
            $account_description = 'Mail account for email alerts'
            $profilename = "dbatoolsci_test_$(Get-Random)"
            $profile_description = 'Mail profile for email alerts'

            $email_address = 'dbatoolssci@dbatools.io'
            $mailserver_name = 'smtp.dbatools.io'
            $replyto_address = 'no-reply@dbatools.io'
            $mailaccountpriority = 1

            $splat1 = @{
                SqlInstance    = $global:instance2
                Name           = $accountName
                Description    = $account_description
                EmailAddress   = $email_address
                DisplayName    = $account_display_name
                ReplyToAddress = $replyto_address
                MailServer     = $mailserver_name
            }
            $null = New-DbaDbMailAccount @splat1 -Force

            $splat2 = @{
                SqlInstance         = $global:instance2
                Name                = $profilename
                Description         = $profile_description
                MailAccountName     = $email_address
                MailAccountPriority = $mailaccountpriority
            }
            $null = New-DbaDbMailProfile @splat2
        }

        AfterAll {
            $servers = Connect-DbaInstance -SqlInstance $global:instance2, $global:instance3

            foreach ($s in $servers) {
                $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$accountname';"
                Invoke-DbaQuery -SqlInstance $s -Query $mailAccountSettings -Database msdb
                $mailProfileSettings = "EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = '$profilename';"
                Invoke-DbaQuery -SqlInstance $s -Query $mailProfileSettings -Database msdb
            }
        }

        Context "Copy DbMail to $global:instance3" {
            BeforeAll {
                $results = Copy-DbaDbMail -Source $global:instance2 -Destination $global:instance3
            }

            It "Should have copied database mailitems" {
                $results | Should -Not -BeNullOrEmpty
            }

            It "Should have copied <_.type> from $global:instance2 to $global:instance3" -ForEach ($results | Where-Object { $_.type -in @('Mail Configuration', 'Mail Account', 'Mail Profile') }) {
                $_.SourceServer | Should -Be "$global:instance2"
                $_.DestinationServer | Should -Be "$global:instance3"
            }
        }

        Context "Copy MailServers specifically" {
            BeforeAll {
                $results = Copy-DbaDbMail -Source $global:instance2 -Destination $global:instance3 -Type MailServers
            }

            It "Should have copied database mailitems" {
                $results | Should -Not -BeNullOrEmpty
            }

            It "Should have skipped <_.type> from $global:instance2 to $global:instance3" -ForEach $results {
                $_.SourceServer | Should -Be "$global:instance2"
                $_.DestinationServer | Should -Be "$global:instance3"
                $_.Status | Should -Be 'Skipped'
            }
        }
    }
}
