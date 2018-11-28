$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 3
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaAgentServer).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command gets server agent" {
        $results = Get-DbaAgentServer -SqlInstance $script:instance2
        It "Should get 1 agent server" {
            $results.count | Should Be 1
        }

        It "returns the correct properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,AgentDomainGroup,AgentLogLevel,AgentMailType,AgentShutdownWaitTime,ErrorLogFile,IdleCpuDuration,IdleCpuPercentage,IsCpuPollingEnabled,JobServerType,LoginTimeout,JobHistoryIsEnabled,MaximumHistoryRows,MaximumJobHistoryRows,MsxAccountCredentialName,MsxAccountName,MsxServerName,Name,NetSendRecipient,ServiceAccount,ServiceStartMode,SqlAgentAutoStart,SqlAgentMailProfile,SqlAgentRestart,SqlServerRestart,State,SysAdminOnly'.Split(',')
            ($results.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

    }
}