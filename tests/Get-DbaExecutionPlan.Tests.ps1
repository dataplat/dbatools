#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaExecutionPlan",
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
                "SinceCreation",
                "SinceLastExecution",
                "ExcludeEmptyQueryPlan",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Skip IntegrationTests on AppVeyor because tests take too long

    Context "Gets Execution Plan" {
        BeforeAll {
            $allResults = @(Get-DbaExecutionPlan -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput" | Where-Object statementtype -eq "SELECT" | Select-Object -First 1)
        }

        It "Gets results" {
            $allResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "Gets Execution Plan when using -Database" {
        BeforeAll {
            $databaseResults = @(Get-DbaExecutionPlan -SqlInstance $TestConfig.InstanceSingle -Database Master | Select-Object -First 1)
        }

        It "Gets results" {
            $databaseResults | Should -Not -BeNullOrEmpty
        }

        It "Should be execution plan on Master" {
            $databaseResults.DatabaseName | Should -Be "Master"
        }
    }

    Context "Gets no Execution Plan when using -ExcludeDatabase" {
        BeforeAll {
            $excludeResults = @(Get-DbaExecutionPlan -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase Master | Select-Object -First 1)
        }

        It "Gets results" {
            $excludeResults | Should -Not -BeNullOrEmpty
        }

        It "Should be execution plan on Master" {
            $excludeResults.DatabaseName | Should -Not -Be "Master"
        }
    }

    Context "Gets Execution Plan when using -SinceCreation" {
        BeforeAll {
            $creationResults = @(Get-DbaExecutionPlan -SqlInstance $TestConfig.InstanceSingle -Database Master -SinceCreation "01-01-2000" | Select-Object -First 1)
        }

        It "Gets results" {
            $creationResults | Should -Not -BeNullOrEmpty
        }

        It "Should be execution plan on Master" {
            $creationResults.DatabaseName | Should -Be "Master"
        }

        It "Should have a creation date Greater than 01-01-2000" {
            $creationResults.CreationTime | Should -BeGreaterThan "01-01-2000"
        }
    }

    Context "Gets Execution Plan when using -SinceLastExecution" {
        BeforeAll {
            $executionResults = @(Get-DbaExecutionPlan -SqlInstance $TestConfig.InstanceSingle -Database Master -SinceLastExecution "01-01-2000" | Select-Object -First 1)
        }

        It "Gets results" {
            $executionResults | Should -Not -BeNullOrEmpty
        }

        It "Should be execution plan on Master" {
            $executionResults.DatabaseName | Should -Be "Master"
        }

        It "Should have a execution time Greater than 01-01-2000" {
            $executionResults.LastExecutionTime | Should -BeGreaterThan "01-01-2000"
        }
    }

    Context "Gets Execution Plan when using -ExcludeEmptyQueryPlan" {
        BeforeAll {
            $emptyPlanResults = @(Get-DbaExecutionPlan -SqlInstance $TestConfig.InstanceSingle -ExcludeEmptyQueryPlan)
        }

        It "Gets no results" {
            $emptyPlanResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "ObjectName",
                "QueryPosition",
                "SqlHandle",
                "PlanHandle",
                "CreationTime",
                "LastExecutionTime",
                "StatementCondition",
                "StatementSimple",
                "StatementId",
                "StatementCompId",
                "StatementType",
                "RetrievedFromCache",
                "StatementSubTreeCost",
                "StatementEstRows",
                "SecurityPolicyApplied",
                "StatementOptmLevel",
                "QueryHash",
                "QueryPlanHash",
                "StatementOptmEarlyAbortReason",
                "CardinalityEstimationModelVersion",
                "ParameterizedText",
                "StatementSetOptions",
                "QueryPlan",
                "BatchConditionXml",
                "BatchSimpleXml",
                "BatchQueryPlanRaw",
                "SingleStatementPlanRaw",
                "PlanWarnings"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "ObjectName",
                "QueryPosition",
                "SqlHandle",
                "PlanHandle",
                "CreationTime",
                "LastExecutionTime",
                "StatementCondition",
                "StatementSimple",
                "StatementId",
                "StatementCompId",
                "StatementType",
                "RetrievedFromCache",
                "StatementSubTreeCost",
                "StatementEstRows",
                "SecurityPolicyApplied",
                "StatementOptmLevel",
                "QueryHash",
                "QueryPlanHash",
                "StatementOptmEarlyAbortReason",
                "CardinalityEstimationModelVersion",
                "ParameterizedText",
                "StatementSetOptions",
                "QueryPlan",
                "BatchConditionXml",
                "BatchSimpleXml"
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