$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Source', 'Destination', 'Type', 'SourceSqlCredential', 'DestinationSqlCredential', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $servers = Connect-DbaInstance -SqlInstance $script:instance2, $script:instance3
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
            SqlInstance    = $script:instance2
            Name           = $accountName
            Description    = $account_description
            EmailAddress   = $email_address
            DisplayName    = $account_display_name
            ReplyToAddress = $replyto_address
            MailServer     = $mailserver_name
        }
        $null = New-DbaDbMailAccount @splat1 -Force

        $splat2 = @{
            SqlInstance         = $script:instance2
            Name                = $profilename
            Description         = $profile_description
            MailAccountName     = $email_address
            MailAccountPriority = $mailaccountpriority
        }
        $null = New-DbaDbMailProfile @splat2

    }
    AfterAll {
        $servers = Connect-DbaInstance -SqlInstance $script:instance2, $script:instance3

        foreach ($s in $servers) {
            $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$accountname';"
            Invoke-DbaQuery -SqlInstance $s -Query $mailAccountSettings -Database msdb
            $mailProfileSettings = "EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = '$profilename';"
            Invoke-DbaQuery -SqlInstance $s -Query $mailProfileSettings -Database msdb

        }
    }

    Context "Copy DbMail to $script:instance3" {
        $results = Copy-DbaDbMail -Source $script:instance2 -Destination $script:instance3

        It "Should have copied database mailitems" {
            $results | Should Not Be $null
        }
        foreach ($r in $results) {
            if ($r.type -in @('Mail Configuration', 'Mail Account', 'Mail Profile')) {
                It "Should have copied $($r.type) from $script:instance2" {
                    $r.SourceServer | Should Be "$script:instance2"
                }
                It "Should have copied $($r.type) to $script:instance3" {
                    $r.DestinationServer | Should Be "$script:instance3"
                }
            }
        }
    }

    Context "Copy MailServers specifically" {
        $results = Copy-DbaDbMail -Source $script:instance2 -Destination $script:instance3 -Type MailServers

        It "Should have copied database mailitems" {
            $results | Should Not Be $null
        }

        foreach ($r in $results) {
            It "Should have $($r.status) $($r.type) from $script:instance2" {
                $r.SourceServer | Should Be "$script:instance2"
                $r.status | Should Be 'Skipped'
            }
            It "Should have $($r.status) $($r.type) to $script:instance3" {
                $r.DestinationServer | Should Be "$script:instance3"
                $r.status | Should Be 'Skipped'
            }
        }
    }
}