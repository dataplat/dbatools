$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'MasterData', 'MasterLog', 'ErrorLog', 'TraceFlag', 'CommandPromptStart', 'MinimalStart', 'MemoryToReserve', 'SingleUser', 'SingleUserDetails', 'NoLoggingToWinEvents', 'StartAsNamedInstance', 'DisableMonitoring', 'IncreasedExtents', 'TraceFlagOverride', 'StartUpConfig', 'Offline', 'Force', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {

    BeforeAll {
        $defaultInstance = $script:instance1
        $namedInstance = $script:instance2
        $SkipLocalTest = $true # Change to $false to run the tests on a local instance.
    }

    Context "Validate command functionality" {
        # See https://github.com/sqlcollaborative/dbatools/issues/7035
        It -Skip:$SkipLocalTest "Ensure the startup params are not duplicated when more than one server is modified in the same invocation" {
            $result = Set-DbaStartupParameter -SqlInstance $defaultInstance, $namedInstance -TraceFlag 3226 -Confirm:$false

            $resultDefaultInstance = Get-DbaStartupParameter -SqlInstance $defaultInstance
            $resultDefaultInstance.TraceFlags.Count | Should -Be 1
            $resultDefaultInstance.TraceFlags[0] | Should -Be 3226

            # The duplication occurs after the first server is processed.
            $resultNamedInstance = Get-DbaStartupParameter -SqlInstance $namedInstance
            # Using the defaults to test locally
            $resultNamedInstance.MasterData.Count | Should -Be 1
            $resultNamedInstance.MasterLog.Count | Should -Be 1
            $resultNamedInstance.ErrorLog.Count | Should -Be 1

            $resultNamedInstance.TraceFlags.Count | Should -Be 1
            $resultNamedInstance.TraceFlags[0] | Should -Be 3226
        }

        # See https://github.com/sqlcollaborative/dbatools/issues/7035
        It -Skip:$SkipLocalTest "Ensure the correct instance name is returned" {
            $result = Set-DbaStartupParameter -SqlInstance $namedInstance -TraceFlag 3226 -Confirm:$false

            $result.SqlInstance | Should -Be $namedInstance
            $result.TraceFlags.Count | Should -Be 1
            $result.TraceFlags[0] | Should -Be 3226
        }
    }
}