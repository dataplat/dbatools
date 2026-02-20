#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAgentJobCategory",
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
                "Category",
                "CategoryType",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $testCategory1 = "CategoryTest1"
        $testCategory2 = "CategoryTest2"
        $categoriesToCleanup = @()
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategory1, $testCategory2 -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "New Agent Job Category is added properly" {
        It "Should have the right name and category type" {
            $results = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategory1 -OutVariable "global:dbatoolsciOutput"
            $results.Name | Should -Be $testCategory1
            $results.CategoryType | Should -Be "LocalJob"
            $categoriesToCleanup += $testCategory1
        }

        It "Should have the right name and category type" {
            $results = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategory2 -CategoryType MultiServerJob
            $results.Name | Should -Be $testCategory2
            $results.CategoryType | Should -Be "MultiServerJob"
            $categoriesToCleanup += $testCategory2
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategory1, $testCategory2
            $newresults[0].Name | Should -Be $testCategory1
            $newresults[0].CategoryType | Should -Be "LocalJob"
            $newresults[1].Name | Should -Be $testCategory2
            $newresults[1].CategoryType | Should -Be "MultiServerJob"
        }

        It "Should not write over existing job categories" {
            # C# cmdlet routes StopFunction warnings through InvokeCommand.InvokeScript(),
            # which bypasses -WarningVariable capture. Use 3>&1 redirection to capture
            # the warning stream directly.
            $warnings = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategory1 -WarningAction Continue 3>&1 |
                Where-Object { $PSItem -is [System.Management.Automation.WarningRecord] }
            ($warnings.Message -match "already exists").Count | Should -BeGreaterThan 0
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct output type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.JobCategory]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "ID",
                "CategoryType",
                "JobCount"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $typeNames = @($help.returnValues.returnValue.type.name)
            ($typeNames -match "Microsoft\.SqlServer\.Management\.Smo\.Agent\.JobCategory").Count | Should -BeGreaterThan 0
        }
    }
}