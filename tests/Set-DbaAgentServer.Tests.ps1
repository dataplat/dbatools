$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'InputObject', 'AgentLogLevel', 'AgentMailType', 'AgentShutdownWaitTime', 'DatabaseMailProfile', 'ErrorLogFile', 'IdleCpuDuration', 'IdleCpuPercentage', 'CpuPolling', 'LocalHostAlias', 'LoginTimeout', 'MaximumHistoryRows', 'MaximumJobHistoryRows', 'NetSendRecipient', 'ReplaceAlertTokens', 'SaveInSentFolder', 'SqlAgentAutoStart', 'SqlAgentMailProfile', 'SqlAgentRestart', 'SqlServerRestart', 'WriteOemErrorLog', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    $results = Set-DbaAgentServer -SqlInstance $script:instance2 -MaximumHistoryRows 10000 -MaximumJobHistoryRows 100
    It "changes agent server job history properties to 10000 / 100" {
        $results.MaximumHistoryRows | Should Be 10000
        $results.MaximumJobHistoryRows | Should Be 100
    }

    $results = Set-DbaAgentServer -SqlInstance $script:instance2 -CpuPolling Enabled
    It "changes agent server CPU Polling to true" {
        $results.IsCpuPollingEnabled | Should Be $true
    }

    $results = Set-DbaAgentServer -SqlInstance $script:instance2 -CpuPolling Disabled
    It "changes agent server CPU Polling to false" {
        $results.IsCpuPollingEnabled | Should Be $false
    }
}