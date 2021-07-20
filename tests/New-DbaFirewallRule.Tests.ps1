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

    $resultsNew = New-DbaFirewallRule -SqlInstance $script:instance2  -Confirm:$false
    $resultsGet = Get-DbaFirewallRule -SqlInstance $script:instance2
    $resultsRemoveBrowser = $resultsGet | Where-Object { $_.Type -eq "Browser" } | Remove-DbaFirewallRule -Confirm:$false
    $resultsRemove = Remove-DbaFirewallRule -SqlInstance $script:instance2 -Type AllOnComputer -Confirm:$false

    $instanceName = ([DbaInstanceParameter]$script:instance2).InstanceName

    It "creates two firewall rules" {
        $resultsNew.Count | Should -Be 2
    }

    It "creates first firewall rule for SQL Server instance" {
        $resultsNew[0].Successful | Should -Be $true
        $resultsNew[0].Type | Should -Be 'Engine'
        $resultsNew[0].DisplayName | Should -Be "SQL Server instance $instanceName"
        $resultsNew[0].Status | Should -Be 'The rule was successfully created.'
    }

    It "creates second firewall rule for SQL Server Browser" {
        $resultsNew[1].Successful | Should -Be $true
        $resultsNew[1].Type | Should -Be 'Browser'
        $resultsNew[1].DisplayName | Should -Be 'SQL Server instance Browser'
        $resultsNew[1].Status | Should -Be 'The rule was successfully created.'
    }

    It "returns two firewall rules" {
        $resultsGet.Count | Should -Be 2
    }

    It "returns one firewall rule for SQL Server instance" {
        $resultInstance = $resultsGet | Where-Object Type -eq 'Engine'
        $resultInstance.Protocol | Should -Be "TCP"
    }

    It "returns one firewall rule for SQL Server Browser" {
        $resultBrowser = $resultsGet | Where-Object DisplayName -eq 'Browser'
        $resultBrowser.Protocol | Should -Be 'UDP'
        $resultBrowser.LocalPort | Should -Be '1434'
    }

    It "removes firewall rule for Browser" {
        $resultsRemoveBrowser.Type | Should -Be 'Browser'
        $resultsRemoveBrowser.IsRemoved | Should -Be $true
        $resultsRemoveBrowser.Status | Should -Be 'The rule was successfully removed.'
    }

    It "removes other firewall rule" {
        $resultsRemove.Type | Should -Be 'Engine'
        $resultsRemove.IsRemoved | Should -Be $true
        $resultsRemove.Status | Should -Be 'The rule was successfully removed.'
    }
}