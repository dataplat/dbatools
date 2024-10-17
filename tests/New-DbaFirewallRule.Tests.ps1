param($ModuleName = 'dbatools')

Describe "New-DbaFirewallRule" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaFirewallRule
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Credential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String[] -Mandatory:$false
        }
        It "Should have Configuration parameter" {
            $CommandUnderTest | Should -HaveParameter Configuration -Type Hashtable -Mandatory:$false
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $null = Remove-DbaFirewallRule -SqlInstance $global:instance2 -Confirm:$false
        }

        AfterAll {
            $null = Remove-DbaFirewallRule -SqlInstance $global:instance2 -Confirm:$false
        }

        It "creates two firewall rules" {
            $resultsNew = New-DbaFirewallRule -SqlInstance $global:instance2 -Confirm:$false
            $resultsNew.Count | Should -Be 2
        }

        It "creates first firewall rule for SQL Server instance" {
            $resultsNew = New-DbaFirewallRule -SqlInstance $global:instance2 -Confirm:$false
            $instanceName = ([DbaInstanceParameter]$global:instance2).InstanceName
            $resultsNew[0].Successful | Should -Be $true
            $resultsNew[0].Type | Should -Be 'Engine'
            $resultsNew[0].DisplayName | Should -Be "SQL Server instance $instanceName"
            $resultsNew[0].Status | Should -Be 'The rule was successfully created.'
        }

        It "creates second firewall rule for SQL Server Browser" {
            $resultsNew = New-DbaFirewallRule -SqlInstance $global:instance2 -Confirm:$false
            $resultsNew[1].Successful | Should -Be $true
            $resultsNew[1].Type | Should -Be 'Browser'
            $resultsNew[1].DisplayName | Should -Be 'SQL Server Browser'
            $resultsNew[1].Status | Should -Be 'The rule was successfully created.'
        }

        It "returns two firewall rules" {
            $resultsGet = Get-DbaFirewallRule -SqlInstance $global:instance2
            $resultsGet.Count | Should -Be 2
        }

        It "returns one firewall rule for SQL Server instance" {
            $resultsGet = Get-DbaFirewallRule -SqlInstance $global:instance2
            $resultInstance = $resultsGet | Where-Object Type -eq 'Engine'
            $resultInstance.Protocol | Should -Be "TCP"
        }

        It "returns one firewall rule for SQL Server Browser" {
            $resultsGet = Get-DbaFirewallRule -SqlInstance $global:instance2
            $resultBrowser = $resultsGet | Where-Object Type -eq 'Browser'
            $resultBrowser.Protocol | Should -Be 'UDP'
            $resultBrowser.LocalPort | Should -Be '1434'
        }

        It "removes firewall rule for Browser" {
            $resultsGet = Get-DbaFirewallRule -SqlInstance $global:instance2
            $resultsRemoveBrowser = $resultsGet | Where-Object { $_.Type -eq "Browser" } | Remove-DbaFirewallRule -Confirm:$false
            $resultsRemoveBrowser.Type | Should -Be 'Browser'
            $resultsRemoveBrowser.IsRemoved | Should -Be $true
            $resultsRemoveBrowser.Status | Should -Be 'The rule was successfully removed.'
        }

        It "removes other firewall rule" {
            $resultsRemove = Remove-DbaFirewallRule -SqlInstance $global:instance2 -Type AllInstance -Confirm:$false
            $resultsRemove.Type | Should -Be 'Engine'
            $resultsRemove.IsRemoved | Should -Be $true
            $resultsRemove.Status | Should -Be 'The rule was successfully removed.'
        }
    }
}
