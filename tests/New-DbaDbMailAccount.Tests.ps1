$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('WhatIf', 'Confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'DisplayName', 'Description', 'EmailAddress', 'ReplyToAddress', 'MailServer', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $accountName = "dbatoolsci_test_$(get-random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $description = 'Mail account for email alerts'
        $email_address = 'dbatoolssci@dbatools.net'
        $display_name = 'dbatoolsci mail alerts'
        $mailserver_name = 'smtp.dbatools.io'
        $replyto_address = 'no-reply@dbatools.net'

        if ( (Get-DbaSpConfigure -SqlInstance $server -Name 'Database Mail XPs').RunningValue -ne 1 ) {
            Set-DbaSpConfigure -SqlInstance $server -Name 'Database Mail XPs' -Value 1
        }
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$accountName';"
        $server.query($mailAccountSettings)
    }

    Context "Gets DbMail Account" {

        $splat = @{
            SqlInstance    = $script:instance2
            Name           = $accountName
            Description    = $description
            EmailAddress   = $email_address
            DisplayName    = $display_name
            ReplyToAddress = $replyto_address
        }
        $results = New-DbaDbMailAccount @splat

        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have Name of $accountName" {
            $results.Name | Should Be $accountName
        }
        It "Should have Description of 'Mail account for email alerts' " {
            $results.Description | Should Be 'Mail account for email alerts'
        }
        It "Should have EmailAddress of 'dbatoolssci@dbatools.net' " {
            $results.EmailAddress | Should Be 'dbatoolssci@dbatools.net'
        }
        It "Should have ReplyToAddress of 'no-reply@dbatools.net' " {
            $results.ReplyToAddress | Should Be 'no-reply@dbatools.net'
        }
        It -Skip "Should have MailServer of '[smtp.dbatools.io]' " {
            $results.MailServers | Should Be '[smtp.dbatools.io]'
        }
    }
    Context "Gets DbMail when using -Account" {
        $results = Get-DbaDbMailAccount -SqlInstance $server -Account $accountName
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have Name of $accountName" {
            $results.name | Should Be $accountName
        }
        It "Should have Description of 'Mail account for email alerts' " {
            $results.description | Should Be 'Mail account for email alerts'
        }
        It "Should have EmailAddress of 'dbatoolssci@dbatools.net' " {
            $results.EmailAddress | Should Be 'dbatoolssci@dbatools.net'
        }
        It "Should have ReplyToAddress of 'no-reply@dbatools.net' " {
            $results.ReplyToAddress | Should Be 'no-reply@dbatools.net'
        }
        It -Skip "Should have MailServer of '[smtp.dbatools.io]' " {
            $results.MailServers | Should Be '[smtp.dbatools.io]'
        }
    }
    Context "Gets no DbMail when using -ExcludeAccount" {
        $results = Get-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountName
        It "Gets no results" {
            $results | Should Be $null
        }
    }
}