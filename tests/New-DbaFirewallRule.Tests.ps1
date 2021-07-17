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
    $results = New-DbaFirewallRule -SqlInstance $script:instance2 -Auto -Confirm:$false
    $instanceName = ([DbaInstanceParameter]$script:instance2).InstanceName

    It "creates two firewall rules" {
        $results.Count | Should -Be 2
    }

    It "creates first firewall rule for SQL Server instance" {
        $results[0].DisplayName | Should -Be "SQL Server instance $instanceName"
        $results[0].Successful | Should -Be $true
        $results[0].Warning | Should -Be $null
        $results[0].Error | Should -Be $null
        $results[0].Exception | Should -Be $null
    }

    It "creates second firewall rule for SQL Server Browser" {
        $results[1].DisplayName | Should -Be "SQL Server Browser"
        $results[1].Successful | Should -Be $true
        $results[1].Warning | Should -Be $null
        $results[1].Error | Should -Be $null
        $results[1].Exception | Should -Be $null
    }
}