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
        $profilename = "dbatoolsci_test_$(get-random)"
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $description = 'Mail account for email alerts'
        $mailaccountname = 'dbatoolssci@dbatools.io'
        $mailaccountpriority = 1

        $sql = "EXECUTE msdb.dbo.sysmail_add_account_sp
        @account_name = '$mailaccountname',
        @description = 'Mail account for administrative e-mail.',
        @email_address = 'dba@ad.local',
        @display_name = 'Automated Mailer',
        @mailserver_name = 'smtp.ad.local'"
        $server.Query($sql)
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = '$profilename';"
        $server.query($mailAccountSettings)
        $regularaccountsettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$mailaccountname';"
        $server.query($regularaccountsettings)
    }

    Context "Sets DbMail Profile" {

        $splat = @{
            SqlInstance         = $script:instance2
            Name                = $profilename
            Description         = $description
            MailAccountName     = $mailaccountname
            MailAccountPriority = $mailaccountpriority
        }
        $results = New-DbaDbMailProfile @splat

        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have Name of $profilename" {
            $results.name | Should Be $profilename
        }
        It "Should have Description of $description " {
            $results.description | Should Be $description
        }
    }
}