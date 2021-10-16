$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'LogCount', 'LogSize', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $logfiles = $server.NumberOfLogFiles
        $logsize = $server.ErrorLogSizeKb

        $server.NumberOfLogFiles = 4
        $server.ErrorLogSizeKb = 1024
        $server.Alter()

        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $logfiles2 = $server.NumberOfLogFiles
        $logsize2 = $server.ErrorLogSizeKb

        $server.NumberOfLogFiles = 4
        $server.Alter()
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $server.NumberOfLogFiles = $logfiles2
        $server.Alter()

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.NumberOfLogFiles = $logfiles
        $server.ErrorLogSizeKb = $logsize
        $server.Alter()
    }

    Context "Apply LogCount to multiple instances" {
        $results = Set-DbaErrorLogConfig -SqlInstance $script:instance2, $script:instance1 -LogCount 8
        foreach ($result in $results) {
            It 'Returns LogCount set to 8 for each instance' {
                $result.LogCount | Should Be 8
            }
        }
    }
    Context "Apply LogSize to multiple instances" {
        $results = Set-DbaErrorLogConfig -SqlInstance $script:instance2, $script:instance1 -LogSize 100 -WarningAction SilentlyContinue -WarningVariable warn2
        foreach ($result in $results) {
            It 'Returns LogSize set to 100 for each instance' {
                $result.LogSize.Kilobyte | Should Be 100
            }
        }

        It "returns a warning for invalid version" {
            $warn2 | Should Match 'not supported'
        }
    }
}