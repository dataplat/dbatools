param($ModuleName = 'dbatools')

Describe "Sync-DbaAvailabilityGroup" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Sync-DbaAvailabilityGroup
        }

        It "has all the required parameters" {
            $params = @(
                "Primary",
                "PrimarySqlCredential",
                "Secondary",
                "SecondarySqlCredential",
                "AvailabilityGroup",
                "Exclude",
                "Login",
                "ExcludeLogin",
                "Job",
                "ExcludeJob",
                "DisableJobOnDestination",
                "InputObject",
                "Force",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            $params | ForEach-Object {
                It "has the required parameter: <_>" {
                    $CommandUnderTest | Should -HaveParameter $PSItem
                }
            }
        }
    }
}

<#
    Integration tests are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance
#>
