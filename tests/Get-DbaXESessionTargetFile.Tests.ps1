param($ModuleName = 'dbatools')

Describe "Get-DbaXESessionTargetFile" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
        #Loading this function is needed since it is currently not in the manifest
        . "$PSScriptRoot\..\public\Get-DbaXESessionTargetFile.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaXESessionTargetFile
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Session",
            "Target",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
