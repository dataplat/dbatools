$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'ExcludeAccount', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeEach {

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server2 = Connect-DbaInstance -SqlInstance $script:instance3
        $accountname = "dbatoolsci_test_$(get-random)"
        $accountname2 = "dbatoolsci_test_$(get-random)"

        $null = New-DbaDbMailAccount -SqlInstance $server, $server2 -Name $accountname -EmailAddress admin@ad.local
        $null = New-DbaDbMailAccount -SqlInstance $server, $server2 -Name $accountname2 -EmailAddress admin@ad.local

    }

    Context "commands work as expected" {

        It "removes a database mail account" {
            (Get-DbaDbMailAccount -SqlInstance $server, $server2 -Name $accountname ) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server, $server2 -Name $accountname -Confirm:$false
            (Get-DbaDbMailAccount -SqlInstance $server, $server2 -Name $accountname ) | Should -BeNullOrEmpty
        }

        It "supports piping database mail account" {
            (Get-DbaDbMailAccount -SqlInstance $server, $server2 -Name $accountname ) | Should -Not -BeNullOrEmpty
            Get-DbaDbMailAccount -SqlInstance $server, $server2 -Name $accountname | Remove-DbaDbMailAccount -Confirm:$false
            (Get-DbaDbMailAccount -SqlInstance $server, $server2 -Name $accountname ) | Should -BeNullOrEmpty
        }

        It "removes all database mail accounts but excluded" {
            (Get-DbaDbMailAccount -SqlInstance $server, $server2 -Name $accountname2 ) | Should -Not -BeNullOrEmpty
            (Get-DbaDbMailAccount -SqlInstance $server, $server2 -ExcludeAccount $accountname2 ) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server, $server2 -ExcludeAccount $accountname2 -Confirm:$false
            (Get-DbaDbMailAccount -SqlInstance $server, $server2 -ExcludeAccount $accountname2 ) | Should -BeNullOrEmpty
            (Get-DbaDbMailAccount -SqlInstance $server, $server2 -Name $accountname2 ) | Should -Not -BeNullOrEmpty
        }

        It "removes all database mail accounts" {
            (Get-DbaDbMailAccount -SqlInstance $server, $server2 ) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server, $server2 -Confirm:$false
            (Get-DbaDbMailAccount -SqlInstance $server, $server2 ) | Should -BeNullOrEmpty
        }
    }
}