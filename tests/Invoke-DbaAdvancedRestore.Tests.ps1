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
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "BackupHistory",
                "SqlInstance",
                "SqlCredential",
                "OutputScriptOnly",
                "VerifyOnly",
                "RestoreTime",
                "StandbyDirectory",
                "NoRecovery",
                "MaxTransferSize",
                "BlockSize",
                "BufferCount",
                "Continue",
                "AzureCredential",
                "WithReplace",
                "KeepReplication",
                "KeepCDC",
                "PageRestore",
                "ExecuteAs",
                "StopBefore",
                "StopMark",
                "StopAfterDate",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
