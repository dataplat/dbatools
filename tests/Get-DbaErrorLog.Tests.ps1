#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaErrorLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Correctly gets error log messages" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $sourceFilter = "Logon"
            $textFilter = "All rights reserved"
            $login = "DaperDan"

            $existingLogin = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login $login
            if ($existingLogin) {
                Get-DbaProcess -SqlInstance $TestConfig.instance1 -Login $login | Stop-DbaProcess
                $existingLogin.Drop()
            }

            # (1) Cycle errorlog message: The error log has been reinitialized
            $sql = "EXEC sp_cycle_errorlog;"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $null = $server.Query($sql)

            # (2) Need a login failure, source would be Logon
            $pwd = "p0w3rsh3llrules" | ConvertTo-SecureString -Force -AsPlainText
            $sqlCred = New-Object System.Management.Automation.PSCredential($login, $pwd)
            try {
                Connect-DbaInstance -SqlInstance $TestConfig.instance1 -SqlCredential $sqlCred -ErrorVariable $whatever
            } catch { }

            # Get date filters for After/Before tests
            $afterLog = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 1 | Select-Object -First 1
            $beforeLog = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 1 | Select-Object -Last 1
            $afterFilter = $afterLog.LogDate.AddMinutes(+1)
            $beforeFilter = $beforeLog.LogDate.AddMinutes(-1)

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup test login if it exists
            $testLogin = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login $login -ErrorAction SilentlyContinue
            if ($testLogin) {
                Get-DbaProcess -SqlInstance $TestConfig.instance1 -Login $login | Stop-DbaProcess -ErrorAction SilentlyContinue
                $testLogin.Drop()
            }
        }

        It "Has the correct default properties" {
            $expectedProps = "ComputerName", "InstanceName", "SqlInstance", "LogDate", "Source", "Text"
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 0
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Returns filtered results for [Source = $sourceFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -Source $sourceFilter
            $results[0].Source | Should -Be $sourceFilter
        }

        It "Returns filtered result for [LogNumber = 0] and [Source = $sourceFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 0 -Source $sourceFilter
            $results[0].Source | Should -Be $sourceFilter
        }

        It "Returns filtered results for [Text = $textFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -Text $textFilter
            { $results[0].Text -like "*$textFilter*" } | Should -Be $true
        }

        It "Returns filtered result for [LogNumber = 0] and [Text = $textFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 0 -Text $textFilter
            { $results[0].Text -like "*$textFilter*" } | Should -Be $true
        }

        It "Returns filtered results for [After = $afterFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -After $afterFilter
            { $results[0].LogDate -ge $afterFilter } | Should -Be $true
        }

        It "Returns filtered results for [LogNumber = 1] and [After = $afterFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 1 -After $afterFilter
            { $results[0].LogDate -ge $afterFilter } | Should -Be $true
        }

        It "Returns filtered result for [Before = $beforeFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -Before $beforeFilter
            { $results[-1].LogDate -le $beforeFilter } | Should -Be $true
        }

        It "Returns filtered result for [LogNumber = 1] and [Before = $beforeFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 1 -Before $beforeFilter
            { $results[-1].LogDate -le $beforeFilter } | Should -Be $true
        }
    }
}