#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaErrorLog",
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
                "SqlInstance",
                "SqlCredential",
                "LogNumber",
                "Source",
                "Text",
                "After",
                "Before",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Correctly gets error log messages" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            $global:sourceFilter = "Logon"
            $global:textFilter = "All rights reserved"
            $testLogin = "DaperDan"

            $existingLogin = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login $testLogin
            if ($existingLogin) {
                Get-DbaProcess -SqlInstance $TestConfig.instance1 -Login $testLogin | Stop-DbaProcess
                $existingLogin.Drop()
            }

            # (1) Cycle errorlog message: The error log has been reinitialized
            $sqlCycleLog = "EXEC sp_cycle_errorlog;"
            $serverConnection = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $null = $serverConnection.Query($sqlCycleLog)

            # (2) Need a login failure, source would be Logon
            $testPassword = "p0w3rsh3llrules" | ConvertTo-SecureString -Force -AsPlainText
            $testCredential = New-Object System.Management.Automation.PSCredential($testLogin, $testPassword)
            try {
                Connect-DbaInstance -SqlInstance $TestConfig.instance1 -SqlCredential $testCredential -ErrorVariable $null
            } catch { }

            # Get sample data for date filtering tests
            $global:sampleLogEntry = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 1 | Select-Object -First 1
            $global:lastLogEntry = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 1 | Select-Object -Last 1

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            # Cleanup test login if it still exists
            $cleanupLogin = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login "DaperDan" -ErrorAction SilentlyContinue
            if ($cleanupLogin) {
                $cleanupLogin.Drop()
            }
        }
        It "Has the correct default properties" {
            $expectedProps = "ComputerName,InstanceName,SqlInstance,LogDate,Source,Text".Split(",")
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 0
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Returns filtered results for [Source = $global:sourceFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -Source $global:sourceFilter
            $results[0].Source | Should -Be $global:sourceFilter
        }

        It "Returns filtered result for [LogNumber = 0] and [Source = $global:sourceFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 0 -Source $global:sourceFilter
            $results[0].Source | Should -Be $global:sourceFilter
        }

        It "Returns filtered results for [Text = $global:textFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -Text $global:textFilter
            ($results[0].Text -like "*$global:textFilter*") | Should -BeTrue
        }

        It "Returns filtered result for [LogNumber = 0] and [Text = $global:textFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 0 -Text $global:textFilter
            ($results[0].Text -like "*$global:textFilter*") | Should -BeTrue
        }

        It "Returns filtered results for After parameter" {
            $afterFilter = $global:sampleLogEntry.LogDate.AddMinutes(+1)
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -After $afterFilter
            ($results[0].LogDate -ge $afterFilter) | Should -BeTrue
        }

        It "Returns filtered results for [LogNumber = 1] and After parameter" {
            $afterFilter = $global:sampleLogEntry.LogDate.AddMinutes(+1)
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 1 -After $afterFilter
            ($results[0].LogDate -ge $afterFilter) | Should -BeTrue
        }

        It "Returns filtered result for Before parameter" {
            $beforeFilter = $global:lastLogEntry.LogDate.AddMinutes(-1)
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -Before $beforeFilter
            ($results[-1].LogDate -le $beforeFilter) | Should -BeTrue
        }

        It "Returns filtered result for [LogNumber = 1] and Before parameter" {
            $beforeFilter = $global:lastLogEntry.LogDate.AddMinutes(-1)
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 1 -Before $beforeFilter
            ($results[-1].LogDate -le $beforeFilter) | Should -BeTrue
        }
    }
}