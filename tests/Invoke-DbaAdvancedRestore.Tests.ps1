param($ModuleName = 'dbatools')

Describe "Invoke-DbaAdvancedRestore" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaAdvancedRestore
        }
        It "Should have BackupHistory parameter" {
            $CommandUnderTest | Should -HaveParameter BackupHistory
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have OutputScriptOnly parameter" {
            $CommandUnderTest | Should -HaveParameter OutputScriptOnly
        }
        It "Should have VerifyOnly parameter" {
            $CommandUnderTest | Should -HaveParameter VerifyOnly
        }
        It "Should have RestoreTime parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreTime
        }
        It "Should have StandbyDirectory parameter" {
            $CommandUnderTest | Should -HaveParameter StandbyDirectory
        }
        It "Should have NoRecovery parameter" {
            $CommandUnderTest | Should -HaveParameter NoRecovery
        }
        It "Should have MaxTransferSize parameter" {
            $CommandUnderTest | Should -HaveParameter MaxTransferSize
        }
        It "Should have BlockSize parameter" {
            $CommandUnderTest | Should -HaveParameter BlockSize
        }
        It "Should have BufferCount parameter" {
            $CommandUnderTest | Should -HaveParameter BufferCount
        }
        It "Should have Continue parameter" {
            $CommandUnderTest | Should -HaveParameter Continue
        }
        It "Should have AzureCredential parameter" {
            $CommandUnderTest | Should -HaveParameter AzureCredential
        }
        It "Should have WithReplace parameter" {
            $CommandUnderTest | Should -HaveParameter WithReplace
        }
        It "Should have KeepReplication parameter" {
            $CommandUnderTest | Should -HaveParameter KeepReplication
        }
        It "Should have KeepCDC parameter" {
            $CommandUnderTest | Should -HaveParameter KeepCDC
        }
        It "Should have PageRestore parameter" {
            $CommandUnderTest | Should -HaveParameter PageRestore
        }
        It "Should have ExecuteAs parameter" {
            $CommandUnderTest | Should -HaveParameter ExecuteAs
        }
        It "Should have StopBefore parameter" {
            $CommandUnderTest | Should -HaveParameter StopBefore
        }
        It "Should have StopMark parameter" {
            $CommandUnderTest | Should -HaveParameter StopMark
        }
        It "Should have StopAfterDate parameter" {
            $CommandUnderTest | Should -HaveParameter StopAfterDate
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
