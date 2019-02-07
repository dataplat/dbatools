$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'Description', 'AccountName', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $accountname = "dbatoolsci_test_$(get-random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $description = 'Mail account for email alerts'
        $name = 'dbatoolssci@dbatools.io'
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_profile_sp
            @account_name = '$accountname';"
        $server.query($mailAccountSettings)
    }

    Context "Gets DbMail Profile" {

        $splat = @{
            SqlInstance    = $script:instance2
            Name           = $accountname
            Description    = $description
            DisplayName    = $display_name
        }
        $results = New-DbaDbMailProfile @splat

        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have Name of $accounName" {
            $results.name | Should Be $accountname
        }
        It "Should have Desctiption of 'Mail account for email alerts' " {
            $results.description | Should Be 'Mail account for email alerts'
        }
        It -Skip "Should have MailServer of '[smtp.dbatools.io]' " {
            $results.MailServers | Should Be '[smtp.dbatools.io]'
        }
    }
    Context "Gets DbMail when using -Account" {
        $results = Get-DbaDbMailProfile -SqlInstance $script:instance2 -Account $accountname
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have Name of $accounName" {
            $results.name | Should Be $accountname
        }
        It "Should have Desctiption of 'Mail account for email alerts' " {
            $results.description | Should Be 'Mail account for email alerts'
        }
        It "Should have MailServer of '[smtp.dbatools.io]' " {
            $results.MailServers | Should Be '[smtp.dbatools.io]'
        }
    }
    Context "Gets no DbMail when using -ExcludeAccount" {
        $results = Get-DbaDbMailProfile -SqlInstance $script:instance2 -ExcludeAccount $accountname
        It "Gets no results" {
            $results | Should Be $null
        }
    }
}