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
            $CommandUnderTest | Should -HaveParameter BackupHistory -Type Object[]
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have OutputScriptOnly parameter" {
            $CommandUnderTest | Should -HaveParameter OutputScriptOnly -Type SwitchParameter
        }
        It "Should have VerifyOnly parameter" {
            $CommandUnderTest | Should -HaveParameter VerifyOnly -Type SwitchParameter
        }
        It "Should have RestoreTime parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreTime -Type DateTime
        }
        It "Should have StandbyDirectory parameter" {
            $CommandUnderTest | Should -HaveParameter StandbyDirectory -Type String
        }
        It "Should have NoRecovery parameter" {
            $CommandUnderTest | Should -HaveParameter NoRecovery -Type SwitchParameter
        }
        It "Should have MaxTransferSize parameter" {
            $CommandUnderTest | Should -HaveParameter MaxTransferSize -Type Int32
        }
        It "Should have BlockSize parameter" {
            $CommandUnderTest | Should -HaveParameter BlockSize -Type Int32
        }
        It "Should have BufferCount parameter" {
            $CommandUnderTest | Should -HaveParameter BufferCount -Type Int32
        }
        It "Should have Continue parameter" {
            $CommandUnderTest | Should -HaveParameter Continue -Type SwitchParameter
        }
        It "Should have AzureCredential parameter" {
            $CommandUnderTest | Should -HaveParameter AzureCredential -Type String
        }
        It "Should have WithReplace parameter" {
            $CommandUnderTest | Should -HaveParameter WithReplace -Type SwitchParameter
        }
        It "Should have KeepReplication parameter" {
            $CommandUnderTest | Should -HaveParameter KeepReplication -Type SwitchParameter
        }
        It "Should have KeepCDC parameter" {
            $CommandUnderTest | Should -HaveParameter KeepCDC -Type SwitchParameter
        }
        It "Should have PageRestore parameter" {
            $CommandUnderTest | Should -HaveParameter PageRestore -Type Object[]
        }
        It "Should have ExecuteAs parameter" {
            $CommandUnderTest | Should -HaveParameter ExecuteAs -Type String
        }
        It "Should have StopBefore parameter" {
            $CommandUnderTest | Should -HaveParameter StopBefore -Type SwitchParameter
        }
        It "Should have StopMark parameter" {
            $CommandUnderTest | Should -HaveParameter StopMark -Type String
        }
        It "Should have StopAfterDate parameter" {
            $CommandUnderTest | Should -HaveParameter StopAfterDate -Type DateTime
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
