param($ModuleName = 'dbatools')

Describe "Set-DbaStartupParameter" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $defaultInstance = $global:instance1
        $namedInstance = $global:instance2
        $SkipLocalTest = $true # Change to $false to run the tests on a local instance.
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaStartupParameter
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Credential",
            "MasterData",
            "MasterLog",
            "ErrorLog",
            "TraceFlag",
            "CommandPromptStart",
            "MinimalStart",
            "MemoryToReserve",
            "SingleUser",
            "SingleUserDetails",
            "NoLoggingToWinEvents",
            "StartAsNamedInstance",
            "DisableMonitoring",
            "IncreasedExtents",
            "TraceFlagOverride",
            "StartupConfig",
            "Offline",
            "Force",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Validate command functionality" -Skip:$SkipLocalTest {
        It "Ensure the startup params are not duplicated when more than one server is modified in the same invocation" {
            $result = Set-DbaStartupParameter -SqlInstance $defaultInstance, $namedInstance -TraceFlag 3226

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

        It "Ensure the correct instance name is returned" {
            $result = Set-DbaStartupParameter -SqlInstance $namedInstance -TraceFlag 3226

            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.TraceFlags.Count | Should -Be 1
            $result.TraceFlags[0] | Should -Be 3226
        }
    }
}
