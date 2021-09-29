$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Profile', 'ExcludeProfile', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeEach {

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server2 = Connect-DbaInstance -SqlInstance $script:instance3
        $profilename = "dbatoolsci_test_$(get-random)"
        $profilename2 = "dbatoolsci_test_$(get-random)"

        $null = New-DbaDbMailProfile -SqlInstance $server, $server2 -Name $profilename
        $null = New-DbaDbMailProfile -SqlInstance $server, $server2 -Name $profilename2

    }

    Context "commands work as expected" {

        It "removes a database mail profile" {
            (Get-DbaDbMailProfile -SqlInstance $server, $server2 -Profile $profilename ) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailProfile -SqlInstance $server, $server2 -Profile $profilename -Confirm:$false
            (Get-DbaDbMailProfile -SqlInstance $server, $server2 -Profile $profilename ) | Should -BeNullOrEmpty
        }

        It "supports piping database mail profile" {
            (Get-DbaDbMailProfile -SqlInstance $server, $server2 -Profile $profilename ) | Should -Not -BeNullOrEmpty
            Get-DbaDbMailProfile -SqlInstance $server, $server2 -Profile $profilename | Remove-DbaDbMailProfile -Confirm:$false
            (Get-DbaDbMailProfile -SqlInstance $server, $server2 -Profile $profilename ) | Should -BeNullOrEmpty
        }

        It "removes all database mail profiles but excluded" {
            (Get-DbaDbMailProfile -SqlInstance $server, $server2 -Profile $profilename2 ) | Should -Not -BeNullOrEmpty
            (Get-DbaDbMailProfile -SqlInstance $server, $server2 -ExcludeProfile $profilename2 ) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailProfile -SqlInstance $server, $server2 -ExcludeProfile $profilename2 -Confirm:$false
            (Get-DbaDbMailProfile -SqlInstance $server, $server2 -ExcludeProfile $profilename2 ) | Should -BeNullOrEmpty
            (Get-DbaDbMailProfile -SqlInstance $server, $server2 -Profile $profilename2 ) | Should -Not -BeNullOrEmpty
        }

        It "removes all database mail profiles" {
            (Get-DbaDbMailProfile -SqlInstance $server, $server2 ) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailProfile -SqlInstance $server, $server2 -Confirm:$false
            (Get-DbaDbMailProfile -SqlInstance $server, $server2 ) | Should -BeNullOrEmpty
        }
    }
}