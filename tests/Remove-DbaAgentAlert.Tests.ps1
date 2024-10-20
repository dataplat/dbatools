param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentAlert Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Import module or set up environment as needed
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentAlert
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Alert",
            "ExcludeAlert",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Remove-DbaAgentAlert Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeEach {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $alertName = "dbatoolsci_test_$(Get-Random)"
        $alertName2 = "dbatoolsci_test_$(Get-Random)"

        $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_alert @name=N'$alertName', @event_description_keyword=N'$alertName', @severity=25"
        $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_alert @name=N'$alertName2', @event_description_keyword=N'$alertName2', @severity=25"
    }

    Context "Remove SQL Agent alerts" {
        It "removes a SQL Agent alert" {
            Get-DbaAgentAlert -SqlInstance $server -Alert $alertName | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $server -Alert $alertName -Confirm:$false
            Get-DbaAgentAlert -SqlInstance $server -Alert $alertName | Should -BeNullOrEmpty
        }

        It "supports piping SQL Agent alert" {
            Get-DbaAgentAlert -SqlInstance $server -Alert $alertName | Should -Not -BeNullOrEmpty
            Get-DbaAgentAlert -SqlInstance $server -Alert $alertName | Remove-DbaAgentAlert -Confirm:$false
            Get-DbaAgentAlert -SqlInstance $server -Alert $alertName | Should -BeNullOrEmpty
        }

        It "removes all SQL Agent alerts but excluded" {
            Get-DbaAgentAlert -SqlInstance $server -Alert $alertName2 | Should -Not -BeNullOrEmpty
            Get-DbaAgentAlert -SqlInstance $server -ExcludeAlert $alertName2 | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $server -ExcludeAlert $alertName2 -Confirm:$false
            Get-DbaAgentAlert -SqlInstance $server -ExcludeAlert $alertName2 | Should -BeNullOrEmpty
            Get-DbaAgentAlert -SqlInstance $server -Alert $alertName2 | Should -Not -BeNullOrEmpty
        }

        It "removes all SQL Agent alerts" {
            Get-DbaAgentAlert -SqlInstance $server | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $server -Confirm:$false
            Get-DbaAgentAlert -SqlInstance $server | Should -BeNullOrEmpty
        }
    }

    AfterEach {
        # Clean up any remaining alerts
        Remove-DbaAgentAlert -SqlInstance $server -Confirm:$false
    }
}
