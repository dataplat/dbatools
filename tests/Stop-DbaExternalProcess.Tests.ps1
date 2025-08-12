#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaExternalProcess",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "ProcessId",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command execution and functionality" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true
            
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "
            -- To allow advanced options to be changed.
            EXECUTE sp_configure 'show advanced options', 1;
            GO
            -- To update the currently configured value for advanced options.
            RECONFIGURE;
            GO
            -- To enable the feature.
            EXECUTE sp_configure 'xp_cmdshell', 1;
            GO
            -- To update the currently configured value for this feature.
            RECONFIGURE;
            GO"

            $query = @"
            xp_cmdshell 'powershell -command ""sleep 20""'
"@
            Start-Process -FilePath sqlcmd -ArgumentList "-S $($TestConfig.instance1) -Q `"$query`"" -NoNewWindow -RedirectStandardOutput null
            
            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
        }

        It "Should stop an external process and return results" {
            $results = Get-DbaExternalProcess -ComputerName localhost | Select-Object -First 1 | Stop-DbaExternalProcess
            $results.ComputerName | Should -Be "localhost"
            $results.Name | Should -Be "cmd.exe"
            $results.ProcessId | Should -Not -Be $null
            $results.Status | Should -Be "Stopped"
        }
    }
}

