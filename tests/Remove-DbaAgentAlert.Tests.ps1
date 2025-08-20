$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Alert', 'ExcludeAlert', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeEach {

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $alertName = "dbatoolsci_test_$(Get-Random)"
        $alertName2 = "dbatoolsci_test_$(Get-Random)"

        $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_alert @name=N'$alertName', @event_description_keyword=N'$alertName', @severity=25"
        $null = Invoke-DbaQuery -SqlInstance $server -Query "EXEC msdb.dbo.sp_add_alert @name=N'$alertName2', @event_description_keyword=N'$alertName2', @severity=25"
    }

    Context "commands work as expected" {

        It "removes a SQL Agent alert" {
            (Get-DbaAgentAlert -SqlInstance $server -Alert $alertName ) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $server -Alert $alertName -Confirm:$false
            (Get-DbaAgentAlert -SqlInstance $server -Alert $alertName ) | Should -BeNullOrEmpty
        }

        It "supports piping SQL Agent alert" {
            (Get-DbaAgentAlert -SqlInstance $server -Alert $alertName ) | Should -Not -BeNullOrEmpty
            Get-DbaAgentAlert -SqlInstance $server -Alert $alertName | Remove-DbaAgentAlert -Confirm:$false
            (Get-DbaAgentAlert -SqlInstance $server -Alert $alertName ) | Should -BeNullOrEmpty
        }

        It "removes all SQL Agent alerts but excluded" {
            (Get-DbaAgentAlert -SqlInstance $server -Alert $alertName2 ) | Should -Not -BeNullOrEmpty
            (Get-DbaAgentAlert -SqlInstance $server -ExcludeAlert $alertName2 ) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $server -ExcludeAlert $alertName2 -Confirm:$false
            (Get-DbaAgentAlert -SqlInstance $server -ExcludeAlert $alertName2 ) | Should -BeNullOrEmpty
            (Get-DbaAgentAlert -SqlInstance $server -Alert $alertName2 ) | Should -Not -BeNullOrEmpty
        }

        It "removes all SQL Agent alerts" {
            (Get-DbaAgentAlert -SqlInstance $server ) | Should -Not -BeNullOrEmpty
            Remove-DbaAgentAlert -SqlInstance $server -Confirm:$false
            (Get-DbaAgentAlert -SqlInstance $server ) | Should -BeNullOrEmpty
        }
    }
}