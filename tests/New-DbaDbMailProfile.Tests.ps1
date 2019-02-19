$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'Description', 'MailAccountName', 'MailAccountPriority', 'EnableException'
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
        $mailaccountname = 'dbatoolssci@dbatools.io'
        $mailaccountpriority = 1
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_profile_sp
            @account_name = '$accountname';"
        $server.query($mailAccountSettings)
    }

    Context "Sets DbMail Profile" {

        $splat = @{
            SqlInstance         = $script:instance2
            Name                = $accountname
            Description         = $description
            MailAccountName     = $mailaccountname
            MailAccountPriority = $mailaccountpriority
        }
        $results = New-DbaDbMailProfile @splat

        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have Name of $accountname" {
            $results.name | Should Be $accountname
        }
        It "Should have Description of $description " {
            $results.description | Should Be $description
        }
        It "Should have MailAccountName of $mailaccountname " {
            $results.mailaccountname | Should Be $mailaccountname
        }
        It "Shoud have a Priority of $mailaccountpriority" {
            $results.mailaccountpriority | Should Be $mailaccountpriority
        }
    }
}