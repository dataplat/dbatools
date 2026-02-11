#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbUserDefinedTableType",
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
                "EnableException",
                "Database",
                "ExcludeDatabase",
                "Type"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $tableTypeName = "dbatools_$(Get-Random)"
        $tableTypeName1 = "dbatools_$(Get-Random)"
        $server.Query("CREATE TYPE $tableTypeName AS TABLE([column1] INT NULL)", "tempdb")
        $server.Query("CREATE TYPE $tableTypeName1 AS TABLE([column1] INT NULL)", "tempdb")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $server.Query("DROP TYPE $tabletypename", "tempdb")
        $null = $server.Query("DROP TYPE $tabletypename1", "tempdb")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets a Db User Defined Table Type" {
        BeforeAll {
            $splatUserDefinedTableType = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Type        = $tableTypeName
            }
            $results = Get-DbaDbUserDefinedTableType @splatUserDefinedTableType
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a name of $tableTypeName" {
            $results.Name | Should -BeExactly $tableTypeName
        }

        It "Should have an owner of dbo" {
            $results.Owner | Should -BeExactly "dbo"
        }

        It "Should have a count of 1" {
            $results.Count | Should -BeExactly 1
        }
    }

    Context "Gets all the Db User Defined Table Type" {
        BeforeAll {
            $results = Get-DbaDbUserDefinedTableType -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a count of 2" {
            $results.Count | Should -BeExactly 2
        }
    }

    Context "Output validation" {
        BeforeAll {
            $splatOutputValidation = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Type        = $tableTypeName
            }
            $result = Get-DbaDbUserDefinedTableType @splatOutputValidation
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.UserDefinedTableType"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ID",
                "Name",
                "Columns",
                "Owner",
                "CreateDate",
                "IsSystemObject",
                "Version"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}