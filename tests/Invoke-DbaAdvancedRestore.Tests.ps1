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
            $CommandUnderTest | Should -HaveParameter BackupHistory -Type System.Object[]
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have OutputScriptOnly parameter" {
            $CommandUnderTest | Should -HaveParameter OutputScriptOnly -Type System.Management.Automation.SwitchParameter
        }
        It "Should have VerifyOnly parameter" {
            $CommandUnderTest | Should -HaveParameter VerifyOnly -Type System.Management.Automation.SwitchParameter
        }
        It "Should have RestoreTime parameter" {
            $CommandUnderTest | Should -HaveParameter RestoreTime -Type System.DateTime
        }
        It "Should have StandbyDirectory parameter" {
            $CommandUnderTest | Should -HaveParameter StandbyDirectory -Type System.String
        }
        It "Should have NoRecovery parameter" {
            $CommandUnderTest | Should -HaveParameter NoRecovery -Type System.Management.Automation.SwitchParameter
        }
        It "Should have MaxTransferSize parameter" {
            $CommandUnderTest | Should -HaveParameter MaxTransferSize -Type System.Int32
        }
        It "Should have BlockSize parameter" {
            $CommandUnderTest | Should -HaveParameter BlockSize -Type System.Int32
        }
        It "Should have BufferCount parameter" {
            $CommandUnderTest | Should -HaveParameter BufferCount -Type System.Int32
        }
        It "Should have Continue parameter" {
            $CommandUnderTest | Should -HaveParameter Continue -Type System.Management.Automation.SwitchParameter
        }
        It "Should have AzureCredential parameter" {
            $CommandUnderTest | Should -HaveParameter AzureCredential -Type System.String
        }
        It "Should have WithReplace parameter" {
            $CommandUnderTest | Should -HaveParameter WithReplace -Type System.Management.Automation.SwitchParameter
        }
        It "Should have KeepReplication parameter" {
            $CommandUnderTest | Should -HaveParameter KeepReplication -Type System.Management.Automation.SwitchParameter
        }
        It "Should have KeepCDC parameter" {
            $CommandUnderTest | Should -HaveParameter KeepCDC -Type System.Management.Automation.SwitchParameter
        }
        It "Should have PageRestore parameter" {
            $CommandUnderTest | Should -HaveParameter PageRestore -Type System.Object[]
        }
        It "Should have ExecuteAs parameter" {
            $CommandUnderTest | Should -HaveParameter ExecuteAs -Type System.String
        }
        It "Should have StopBefore parameter" {
            $CommandUnderTest | Should -HaveParameter StopBefore -Type System.Management.Automation.SwitchParameter
        }
        It "Should have StopMark parameter" {
            $CommandUnderTest | Should -HaveParameter StopMark -Type System.String
        }
        It "Should have StopAfterDate parameter" {
            $CommandUnderTest | Should -HaveParameter StopAfterDate -Type System.DateTime
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
