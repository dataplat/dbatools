$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'Credential', 'Auto', 'Configuration', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Remove-DbaFirewallRule -SqlInstance $script:instance2 -Confirm:$false
    }

    AfterAll {
        $null = Remove-DbaFirewallRule -SqlInstance $script:instance2 -Confirm:$false
    }

    $resultsNew = New-DbaFirewallRule -SqlInstance $script:instance2 -Auto -Confirm:$false
    $resultsGet = Get-DbaFirewallRule -SqlInstance $script:instance2
    $resultRemoveBrowser = $resultsGet | Where-Object { $_.DisplayName -eq "SQL Server Browser" } | Remove-DbaFirewallRule -Confirm:$false
    $numberOfRulesAfterBrowserRemove = (Get-DbaFirewallRule -SqlInstance $script:instance2).Count
    $resultRemoveAll = Remove-DbaFirewallRule -SqlInstance $script:instance2 -Confirm:$false
    $numberOfRulesAfterAllRemove = (Get-DbaFirewallRule -SqlInstance $script:instance2).Count

    $instanceName = ([DbaInstanceParameter]$script:instance2).InstanceName

    It "creates two firewall rules" {
        $resultsNew.Count | Should -Be 2
    }

    It "creates first firewall rule for SQL Server instance" {
        $resultsNew[0].DisplayName | Should -Be "SQL Server instance $instanceName"
        $resultsNew[0].Successful | Should -Be $true
        $resultsNew[0].Warning | Should -Be $null
        $resultsNew[0].Error | Should -Be $null
        $resultsNew[0].Exception | Should -Be $null
    }

    It "creates second firewall rule for SQL Server Browser" {
        $resultsNew[1].DisplayName | Should -Be "SQL Server Browser"
        $resultsNew[1].Successful | Should -Be $true
        $resultsNew[1].Warning | Should -Be $null
        $resultsNew[1].Error | Should -Be $null
        $resultsNew[1].Exception | Should -Be $null
    }

    It "returns two firewall rules" {
        $resultsGet.Count | Should -Be 2
    }

    It "returns firewall rules for SQL Server" {
        $resultsGet[0].DisplayName | Should -Be "SQL Server instance $instanceName"
        $resultsGet[1].DisplayName | Should -Be "SQL Server Browser"
    }

    It "returns one firewall rule for SQL Server instance" {
        # This does not return one rule but $null - I don't know why...
        # $resultInstance = $resultsGet | Where-Object Protocol -eq "TCP"
        # $resultInstance.Count | Should -Be 1
        $resultsGet[0].DisplayName | Should -Be "SQL Server instance $instanceName"
        $resultsGet[0].Protocol | Should -Be "TCP"
    }

    It "returns one firewall rule for SQL Server Browser" {
        # This does not return one rule but $null - I don't know why...
        # $resultBrowser = $resultsGet | Where-Object Protocol -eq "UDP"
        # $resultBrowser.Count | Should -Be 1
        $resultsGet[1].DisplayName | Should -Be "SQL Server Browser"
        $resultsGet[1].Protocol | Should -Be "UDP"
        $resultsGet[1].LocalPort | Should -Be "1434"
    }

    It "removes firewall rule for SQL Server Browser from pipeline" {
        $resultRemoveBrowser.Count | Should -Be $null
        $numberOfRulesAfterBrowserRemove | Should -Be 1
    }

    It "removes all firewall rules" {
        $resultRemoveAll = Remove-DbaFirewallRule -SqlInstance $script:instance2 -Confirm:$false
        $resultRemoveAll | Should -Be $null
        $numberOfRulesAfterAllRemove | Should -Be 0
    }
}