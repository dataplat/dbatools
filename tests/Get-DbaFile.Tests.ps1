#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "FileType",
                "Depth",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Returns some files" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $random = Get-Random
            $testDbName = "dbatoolsci_getfile$random"
            $server.Query("CREATE DATABASE $testDbName")

            # Capture results for output validation
            $script:fileResults = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName | Remove-DbaDatabase

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should find the new database file" {
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle
            ($results.Filename -match "dbatoolsci").Count | Should -BeGreaterThan 0
        }

        It "Should find the new database log file" {
            $logPath = (Get-DbaDefaultPath -SqlInstance $TestConfig.InstanceSingle).Log
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -Path $logPath
            ($results.Filename -like "*dbatoolsci*ldf").Count | Should -BeGreaterThan 0
        }

        It "Should find the master database file" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $masterPath = $server.MasterDBPath
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -Path $masterPath
            ($results.Filename -match "master.mdf").Count | Should -BeGreaterThan 0
        }

        It "Returns output of the documented type" {
            $script:fileResults | Should -Not -BeNullOrEmpty
            $script:fileResults[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            $defaultProps = $script:fileResults[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("SqlInstance", "Filename")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Does not include excluded properties in the default display" {
            $defaultProps = $script:fileResults[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $excludedProps = @("ComputerName", "InstanceName", "RemoteFilename")
            foreach ($prop in $excludedProps) {
                $defaultProps | Should -Not -Contain $prop -Because "property '$prop' should be excluded from the default display set"
            }
        }

        It "Has all expected properties available" {
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Filename", "RemoteFilename")
            foreach ($prop in $expectedProps) {
                $script:fileResults[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}