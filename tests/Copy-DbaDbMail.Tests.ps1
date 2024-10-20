param($ModuleName = 'dbatools')

Describe "Copy-DbaDbMail" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

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

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaDbMail
        }
        $params = @(
            "Source",
            "Destination",
            "Type",
            "SourceSqlCredential",
            "DestinationSqlCredential",
            "Force",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Copy DbMail to $global:instance3" {
        BeforeAll {
            $results = Copy-DbaDbMail -Source $global:instance2 -Destination $global:instance3
        }

        It "Should have copied database mailitems" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have copied Mail Configuration from $global:instance2 to $global:instance3" {
            $results | Where-Object { $_.Type -eq 'Mail Configuration' } | Should -Not -BeNullOrEmpty
            $results | Where-Object { $_.Type -eq 'Mail Configuration' } | ForEach-Object {
                $_.SourceServer | Should -Be "$global:instance2"
                $_.DestinationServer | Should -Be "$global:instance3"
            }
        }

        It "Should have copied Mail Account from $global:instance2 to $global:instance3" {
            $results | Where-Object { $_.Type -eq 'Mail Account' } | Should -Not -BeNullOrEmpty
            $results | Where-Object { $_.Type -eq 'Mail Account' } | ForEach-Object {
                $_.SourceServer | Should -Be "$global:instance2"
                $_.DestinationServer | Should -Be "$global:instance3"
            }
        }

        It "Should have copied Mail Profile from $global:instance2 to $global:instance3" {
            $results | Where-Object { $_.Type -eq 'Mail Profile' } | Should -Not -BeNullOrEmpty
            $results | Where-Object { $_.Type -eq 'Mail Profile' } | ForEach-Object {
                $_.SourceServer | Should -Be "$global:instance2"
                $_.DestinationServer | Should -Be "$global:instance3"
            }
        }
    }

    Context "Copy MailServers specifically" {
        BeforeAll {
            $results = Copy-DbaDbMail -Source $global:instance2 -Destination $global:instance3 -Type MailServers
        }

        It "Should have copied database mailitems" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have skipped MailServers from $global:instance2 to $global:instance3" {
            $results | ForEach-Object {
                $_.SourceServer | Should -Be "$global:instance2"
                $_.DestinationServer | Should -Be "$global:instance3"
                $_.Status | Should -Be 'Skipped'
            }
        }
    }
}
