#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaErrorLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

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
            $sourceFilter = "Logon"
            $textFilter = "All rights reserved"
            $loginName = "DaperDan"
            
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            
            $existingLogin = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login $loginName
            if ($existingLogin) {
                Get-DbaProcess -SqlInstance $TestConfig.instance1 -Login $loginName | Stop-DbaProcess
                $existingLogin.Drop()
            }
            
            # (1) Cycle errorlog message: The error log has been reinitialized
            $sqlCycleLog = "EXEC sp_cycle_errorlog;"
            $serverInstance = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $null = $serverInstance.Query($sqlCycleLog)

            # (2) Need a login failure, source would be Logon
            $testPassword = "p0w3rsh3llrules" | ConvertTo-SecureString -Force -AsPlainText
            $testCredential = New-Object System.Management.Automation.PSCredential($loginName, $testPassword)
            try {
                Connect-DbaInstance -SqlInstance $TestConfig.instance1 -SqlCredential $testCredential -ErrorVariable $whatever
            } catch { }
            
            # Get filter dates for After/Before tests
            $afterLogEntry = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 1 | Select-Object -First 1
            $beforeLogEntry = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 1 | Select-Object -Last 1
            
            $global:afterFilter = $afterLogEntry.LogDate.AddMinutes(+1)
            $global:beforeFilter = $beforeLogEntry.LogDate.AddMinutes(-1)
            
            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            
            # Cleanup any remaining test login
            $cleanupLogin = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login $loginName -ErrorAction SilentlyContinue
            if ($cleanupLogin) {
                Get-DbaProcess -SqlInstance $TestConfig.instance1 -Login $loginName -ErrorAction SilentlyContinue | Stop-DbaProcess -ErrorAction SilentlyContinue
                $cleanupLogin.Drop()
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
            $results[0].Text -like "*$textFilter*" | Should -Be $true
        }
        
        It "Returns filtered result for [LogNumber = 0] and [Text = $textFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 0 -Text $textFilter
            $results[0].Text -like "*$textFilter" | Should -Be $true
        }

        It "Returns filtered results for [After = $global:afterFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -After $global:afterFilter
            $results[0].LogDate -ge $global:afterFilter | Should -Be $true
        }
        
        It "Returns filtered results for [LogNumber = 1] and [After = $global:afterFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 1 -After $global:afterFilter
            $results[0].LogDate -ge $global:afterFilter | Should -Be $true
        }
        
        It "Returns filtered result for [Before = $global:beforeFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -Before $global:beforeFilter
            $results[-1].LogDate -le $global:beforeFilter | Should -Be $true
        }
        
        It "Returns filtered result for [LogNumber = 1] and [Before = $global:beforeFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $TestConfig.instance1 -LogNumber 1 -Before $global:beforeFilter
            $results[-1].LogDate -le $global:beforeFilter | Should -Be $true
        }
    }
}
