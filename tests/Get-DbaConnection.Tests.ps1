#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName               = "dbatools",
    $CommandName              = [System.IO.Path]::GetFileName($PSCommandPath.Replace('.Tests.ps1', '')),
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $_ -notin ('WhatIf', 'Confirm') }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                'SqlInstance',
                'SqlCredential',
                'EnableException'
            )
        }
        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "returns the proper transport" {
        BeforeAll {
            $results = Get-DbaConnection -SqlInstance $TestConfig.instance1
        }

        It "returns a valid AuthScheme" {
            foreach ($result in $results) {
                $result.AuthScheme | Should -BeIn 'NTLM', 'Kerberos', 'SQL'
            }
        }
    }
}
