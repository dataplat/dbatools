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
    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'SqlInstance',
                'Filename'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the expected additional properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'RemoteFilename'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available"
            }
        }
    }

    Context "Returns some files" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $random = Get-Random
            $testDbName = "dbatoolsci_getfile$random"
            $server.Query("CREATE DATABASE $testDbName")

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
    }
}