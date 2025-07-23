#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaDbMail" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaDbMail
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "Source",
                "Destination",
                "Type",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "Force",
                "EnableException"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name | Where-Object { $_ -notin ('whatif', 'confirm') }
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaDbMail" -Tags "IntegrationTests" {
    BeforeAll {
        $servers = Connect-DbaInstance -SqlInstance $TestConfig.instance2, $TestConfig.instance3
        foreach ($s in $servers) {
            if ( (Get-DbaSpConfigure -SqlInstance $s -Name 'Database Mail XPs').RunningValue -ne 1 ) {
                Set-DbaSpConfigure -SqlInstance $s -Name 'Database Mail XPs' -Value 1
            }
        }

        $accountName = "dbatoolsci_test_$(get-random)"
        $account_display_name = 'dbatoolsci mail alerts'
        $account_description = 'Mail account for email alerts'
        $profilename = "dbatoolsci_test_$(get-random)"
        $profile_description = 'Mail profile for email alerts'

        $email_address = 'dbatoolssci@dbatools.io'
        $mailserver_name = 'smtp.dbatools.io'
        $replyto_address = 'no-reply@dbatools.io'
        $mailaccountpriority = 1

        $splat1 = @{
            SqlInstance    = $TestConfig.instance2
            Name           = $accountName
            Description    = $account_description
            EmailAddress   = $email_address
            DisplayName    = $account_display_name
            ReplyToAddress = $replyto_address
            MailServer     = $mailserver_name
        }
        $null = New-DbaDbMailAccount @splat1 -Force

        $splat2 = @{
            SqlInstance         = $TestConfig.instance2
            Name                = $profilename
            Description         = $profile_description
            MailAccountName     = $accountName
            MailAccountPriority = $mailaccountpriority
        }
        $null = New-DbaDbMailProfile @splat2
    }

    AfterAll {
        $servers = Connect-DbaInstance -SqlInstance $TestConfig.instance2, $TestConfig.instance3

        foreach ($s in $servers) {
            $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$accountname';"
            Invoke-DbaQuery -SqlInstance $s -Query $mailAccountSettings -Database msdb
            $mailProfileSettings = "EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = '$profilename';"
            Invoke-DbaQuery -SqlInstance $s -Query $mailProfileSettings -Database msdb
        }
    }

    Context "When copying DbMail to $($TestConfig.instance3)" {
        BeforeAll {
            $results = Copy-DbaDbMail -Source $TestConfig.instance2 -Destination $TestConfig.instance3
        }

        It "Should have copied database mail items" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have copied <_.type> from source to destination" -ForEach ($results | Where-Object type -in @('Mail Configuration', 'Mail Account', 'Mail Profile')) {
            $PSItem.SourceServer | Should -Be $TestConfig.instance2
            $PSItem.DestinationServer | Should -Be $TestConfig.instance3
        }
    }

    Context "When copying MailServers specifically" {
        BeforeAll {
            $results = Copy-DbaDbMail -Source $TestConfig.instance2 -Destination $TestConfig.instance3 -Type MailServers
        }

        It "Should have returned results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have skipped <_.type> copy operations" -ForEach $results {
            $PSItem.SourceServer | Should -Be $TestConfig.instance2
            $PSItem.DestinationServer | Should -Be $TestConfig.instance3
            $PSItem.Status | Should -Be 'Skipped'
        }
    }
}
