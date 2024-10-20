param($ModuleName = 'dbatools')

Describe "Set-DbaMaxMemory" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $inst1CurrentMaxValue = (Get-DbaMaxMemory -SqlInstance $global:instance1).MaxValue
        $inst2CurrentMaxValue = (Get-DbaMaxMemory -SqlInstance $global:instance2).MaxValue
    }

    AfterAll {
        $null = Set-DbaMaxMemory -SqlInstance $global:instance1 -Max $inst1CurrentMaxValue
        $null = Set-DbaMaxMemory -SqlInstance $global:instance2 -Max $inst2CurrentMaxValue
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaMaxMemory
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Max",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Connects to multiple instances" {
        BeforeAll {
            $results = Set-DbaMaxMemory -SqlInstance $global:instance1, $global:instance2 -Max 1024
        }
        It 'Returns 1024 for each instance' {
            foreach ($result in $results) {
                $result.MaxValue | Should -Be 1024
            }
        }
    }
}
