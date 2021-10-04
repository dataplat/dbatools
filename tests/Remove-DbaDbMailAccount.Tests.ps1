$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Account', 'ExcludeAccount', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeEach {

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $accountname = "dbatoolsci_test_$(get-random)"
        $accountname2 = "dbatoolsci_test_$(get-random)"

        $null = New-DbaDbMailAccount -SqlInstance $server -Name $accountname -EmailAddress admin@ad.local
        $null = New-DbaDbMailAccount -SqlInstance $server -Name $accountname2 -EmailAddress admin@ad.local

    }

    Context "commands work as expected" {

        It "removes a database mail account" {
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname ) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server -Account $accountname -Confirm:$false
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname ) | Should -BeNullOrEmpty
        }

        It "supports piping database mail account" {
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname ) | Should -Not -BeNullOrEmpty
            Get-DbaDbMailAccount -SqlInstance $server -Account $accountname | Remove-DbaDbMailAccount -Confirm:$false
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname ) | Should -BeNullOrEmpty
        }

        It "removes all database mail accounts but excluded" {
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname2 ) | Should -Not -BeNullOrEmpty
            (Get-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountname2 ) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountname2 -Confirm:$false
            (Get-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountname2 ) | Should -BeNullOrEmpty
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname2 ) | Should -Not -BeNullOrEmpty
        }

        It "removes all database mail accounts" {
            (Get-DbaDbMailAccount -SqlInstance $server ) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server -Confirm:$false
            (Get-DbaDbMailAccount -SqlInstance $server ) | Should -BeNullOrEmpty
        }
    }
}