$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Set-DbaAgentServer).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'InputObject', 'AgentLogLevel', 'AgentMailType', 'AgentShutdownWaitTime', 'DatabaseMailProfile', 'ErrorLogFile', 'IdleCpuDuration', 'IdleCpuPercentage', 'CpuPolling', 'LocalHostAlias', 'LoginTimeout', 'MaximumHistoryRows', 'MaximumJobHistoryRows', 'NetSendRecipient', 'ReplaceAlertTokens', 'SaveInSentFolder', 'SqlAgentAutoStart', 'SqlAgentMailProfile', 'SqlAgentRestart', 'SqlServerRestart', 'WriteOemErrorLog', 'EnableException'
        $paramCount = $knownParameters.Count
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
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