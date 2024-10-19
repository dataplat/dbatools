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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have MasterData as a parameter" {
            $CommandUnderTest | Should -HaveParameter MasterData
        }
        It "Should have MasterLog as a parameter" {
            $CommandUnderTest | Should -HaveParameter MasterLog
        }
        It "Should have ErrorLog as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorLog
        }
        It "Should have TraceFlag as a parameter" {
            $CommandUnderTest | Should -HaveParameter TraceFlag
        }
        It "Should have CommandPromptStart as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter CommandPromptStart
        }
        It "Should have MinimalStart as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter MinimalStart
        }
        It "Should have MemoryToReserve as a parameter" {
            $CommandUnderTest | Should -HaveParameter MemoryToReserve
        }
        It "Should have SingleUser as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter SingleUser
        }
        It "Should have SingleUserDetails as a parameter" {
            $CommandUnderTest | Should -HaveParameter SingleUserDetails
        }
        It "Should have NoLoggingToWinEvents as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoLoggingToWinEvents
        }
        It "Should have StartAsNamedInstance as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter StartAsNamedInstance
        }
        It "Should have DisableMonitoring as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableMonitoring
        }
        It "Should have IncreasedExtents as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncreasedExtents
        }
        It "Should have TraceFlagOverride as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter TraceFlagOverride
        }
        It "Should have StartupConfig as a parameter" {
            $CommandUnderTest | Should -HaveParameter StartupConfig
        }
        It "Should have Offline as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Offline
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
