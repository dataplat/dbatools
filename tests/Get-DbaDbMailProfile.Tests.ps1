$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Profile', 'ExcludeProfile', 'InputObject', 'EnableException'
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
        $mailProfile = "EXEC msdb.dbo.sysmail_add_profile_sp
            @profile_name='$profilename',
            @description='Profile for system email';"
        $server.query($mailProfile)
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $mailProfile = "EXEC msdb.dbo.sysmail_delete_profile_sp
            @profile_name='$profilename';"
        $server.query($mailProfile)
    }

    Context "Gets DbMail Profile" {
        $results = Get-DbaDbMailProfile -SqlInstance $script:instance2 | Where-Object {$_.name -eq "$profilename"}
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have Name of $profilename" {
            $results.name | Should Be $profilename
        }
        It "Should have Desctiption of 'Profile for system email' " {
            $results.description | Should Be 'Profile for system email'
        }
    }
    Context "Gets DbMailProfile when using -Profile" {
        $results = Get-DbaDbMailProfile -SqlInstance $script:instance2 -Profile $profilename
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have Name of $profilename" {
            $results.name | Should Be $profilename
        }
        It "Should have Desctiption of 'Profile for system email' " {
            $results.description | Should Be 'Profile for system email'
        }
    }
    Context "Gets no DbMailProfile when using -ExcludeProfile" {
        $results = Get-DbaDbMailProfile -SqlInstance $script:instance2 -ExcludeProfile $profilename
        It "Gets no results" {
            $results | Should Be $null
        }
    }
}