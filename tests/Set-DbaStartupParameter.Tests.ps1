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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have MasterData as a parameter" {
            $CommandUnderTest | Should -HaveParameter MasterData -Type String
        }
        It "Should have MasterLog as a parameter" {
            $CommandUnderTest | Should -HaveParameter MasterLog -Type String
        }
        It "Should have ErrorLog as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorLog -Type String
        }
        It "Should have TraceFlag as a parameter" {
            $CommandUnderTest | Should -HaveParameter TraceFlag -Type String[]
        }
        It "Should have CommandPromptStart as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter CommandPromptStart -Type Switch
        }
        It "Should have MinimalStart as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter MinimalStart -Type Switch
        }
        It "Should have MemoryToReserve as a parameter" {
            $CommandUnderTest | Should -HaveParameter MemoryToReserve -Type Int32
        }
        It "Should have SingleUser as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter SingleUser -Type Switch
        }
        It "Should have SingleUserDetails as a parameter" {
            $CommandUnderTest | Should -HaveParameter SingleUserDetails -Type String
        }
        It "Should have NoLoggingToWinEvents as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoLoggingToWinEvents -Type Switch
        }
        It "Should have StartAsNamedInstance as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter StartAsNamedInstance -Type Switch
        }
        It "Should have DisableMonitoring as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableMonitoring -Type Switch
        }
        It "Should have IncreasedExtents as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncreasedExtents -Type Switch
        }
        It "Should have TraceFlagOverride as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter TraceFlagOverride -Type Switch
        }
        It "Should have StartupConfig as a parameter" {
            $CommandUnderTest | Should -HaveParameter StartupConfig -Type Object
        }
        It "Should have Offline as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Offline -Type Switch
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Validate command functionality" -Skip:$SkipLocalTest {
        It "Ensure the startup params are not duplicated when more than one server is modified in the same invocation" {
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

        It "Ensure the correct instance name is returned" {
            $result = Set-DbaStartupParameter -SqlInstance $namedInstance -TraceFlag 3226 -Confirm:$false

            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.TraceFlags.Count | Should -Be 1
            $result.TraceFlags[0] | Should -Be 3226
        }
    }
}
