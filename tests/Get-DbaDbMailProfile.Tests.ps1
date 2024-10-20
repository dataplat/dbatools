param($ModuleName = 'dbatools')

Describe "Get-DbaDbMailProfile Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMailProfile
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Profile",
            "ExcludeProfile",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Get-DbaDbMailProfile Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $profilename = "dbatoolsci_test_$(Get-Random)"
    }

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2, $global:instance3
        $mailProfile = "EXEC msdb.dbo.sysmail_add_profile_sp
            @profile_name='$profilename',
            @description='Profile for system email';"
        $server.Query($mailProfile)
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2, $global:instance3
        $mailProfile = "EXEC msdb.dbo.sysmail_delete_profile_sp
            @profile_name='$profilename';"
        $server.Query($mailProfile)
    }

    Context "Gets DbMail Profile" {
        It "Gets results" {
            $results = Get-DbaDbMailProfile -SqlInstance $global:instance2 | Where-Object { $_.Name -eq $profilename }
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Name of $profilename" {
            $results = Get-DbaDbMailProfile -SqlInstance $global:instance2 | Where-Object { $_.Name -eq $profilename }
            $results.Name | Should -Be $profilename
        }

        It "Should have Description of 'Profile for system email'" {
            $results = Get-DbaDbMailProfile -SqlInstance $global:instance2 | Where-Object { $_.Name -eq $profilename }
            $results.Description | Should -Be 'Profile for system email'
        }

        It "Gets results from multiple instances" {
            $results2 = Get-DbaDbMailProfile -SqlInstance $server | Where-Object { $_.Name -eq $profilename }
            $results2 | Should -Not -BeNullOrEmpty
            ($results2 | Select-Object -Property SqlInstance -Unique).Count | Should -Be 2
        }
    }

    Context "Gets DbMailProfile when using -Profile" {
        It "Gets results" {
            $results = Get-DbaDbMailProfile -SqlInstance $global:instance2 -Profile $profilename
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Name of $profilename" {
            $results = Get-DbaDbMailProfile -SqlInstance $global:instance2 -Profile $profilename
            $results.Name | Should -Be $profilename
        }

        It "Should have Description of 'Profile for system email'" {
            $results = Get-DbaDbMailProfile -SqlInstance $global:instance2 -Profile $profilename
            $results.Description | Should -Be 'Profile for system email'
        }
    }

    Context "Gets no DbMailProfile when using -ExcludeProfile" {
        It "Gets no results" {
            $results = Get-DbaDbMailProfile -SqlInstance $global:instance2 -ExcludeProfile $profilename
            $results | Should -Not -Contain $profilename
        }
    }
}
