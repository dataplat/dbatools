#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaQueryExecutionTime",
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
                "Database",
                "ExcludeDatabase",
                "MaxResultsPerDb",
                "MinExecs",
                "MinExecMs",
                "ExcludeSystem",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When getting query execution times" {
        BeforeAll {
            # Use low thresholds to ensure we get results from cached queries
            $splatQuery = @{
                SqlInstance   = $TestConfig.instance1
                Database      = "master"
                MaxResultsPerDb = 10
                MinExecs      = 1
                MinExecMs     = 0
            }
            $results = Get-DbaQueryExecutionTime @splatQuery -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have valid Database values" {
            $results | ForEach-Object { $PSItem.Database | Should -Be "master" }
        }

        It "Should have valid Executions values" {
            $results | ForEach-Object { $PSItem.Executions | Should -BeGreaterOrEqual 1 }
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ProcName",
                "ObjectID",
                "TypeDesc",
                "Executions",
                "AvgExecMs",
                "MaxExecMs",
                "CachedTime",
                "LastExecTime",
                "TotalWorkerTimeMs",
                "TotalElapsedTimeMs",
                "SQLText",
                "FullStatementText"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ProcName",
                "ObjectID",
                "TypeDesc",
                "Executions",
                "AvgExecMs",
                "MaxExecMs",
                "CachedTime",
                "LastExecTime",
                "TotalWorkerTimeMs",
                "TotalElapsedTimeMs",
                "SQLText"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}