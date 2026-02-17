#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaModule",
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
                "ModifiedSince",
                "Type",
                "ExcludeSystemDatabases",
                "ExcludeSystemObjects",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Modules are properly retrieved" {
        BeforeAll {
            # SQL2008R2SP2 will return a number of modules from the msdb database so it is a good candidate to test
            $resultsTyped = Get-DbaModule -SqlInstance $TestConfig.InstanceSingle -Type View -Database msdb -OutVariable "global:dbatoolsciOutput"
        }

        # SQL2008R2SP2 returns around 600 of these in freshly installed instance. 100 is a good enough number.
        It "Should have a high count" {
            $results = Get-DbaModule -SqlInstance $TestConfig.InstanceSingle | Select-Object -First 101
            $results.Count | Should -BeGreaterThan 100
        }

        It "Should only have one type of object" {
            ($resultsTyped | Select-Object -Unique Type | Measure-Object).Count | Should -Be 1
        }

        It "Should only have one database" {
            ($resultsTyped | Select-Object -Unique Database | Measure-Object).Count | Should -Be 1
        }
    }

    Context "Accepts Piped Input" {
        BeforeAll {
            $dbMultiple = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database msdb, master
            # SQL2008R2SP2 returns around 600 of these in freshly installed instance. 100 is a good enough number.
            $resultsPiped = $dbMultiple | Get-DbaModule

            $dbSingle = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database msdb
            $resultsPipedTyped = $dbSingle | Get-DbaModule -Type View
        }

        It "Should have a high count" {
            $resultsPiped.Count | Should -BeGreaterThan 100
        }

        It "Should only have two databases" {
            ($resultsPiped | Select-Object -Unique Database | Measure-Object).Count | Should -Be 2
        }

        It "Should only have one type of object" {
            ($resultsPipedTyped | Select-Object -Unique Type | Measure-Object).Count | Should -Be 1
        }

        It "Should only have one database" {
            ($resultsPipedTyped | Select-Object -Unique Database | Measure-Object).Count | Should -Be 1
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
                "Database",
                "Name",
                "ObjectID",
                "SchemaName",
                "Type",
                "CreateDate",
                "ModifyDate",
                "IsMsShipped",
                "ExecIsStartUp",
                "Definition"
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
                "Name",
                "ObjectID",
                "SchemaName",
                "Type",
                "CreateDate",
                "ModifyDate",
                "IsMsShipped",
                "ExecIsStartUp"
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