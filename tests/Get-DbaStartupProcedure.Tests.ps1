#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaStartupProcedure",
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
                "StartupProcedure",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random
        $startupProc = "dbo.StartUpProc$random"
        $dbname = "master"

        $null = $server.Query("CREATE PROCEDURE $startupProc AS Select 1", $dbname)
        $null = $server.Query("EXEC sp_procoption N'$startupProc', 'startup', '1'", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $server.Query("DROP PROCEDURE $startupProc", $dbname)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When retrieving all startup procedures" {
        BeforeAll {
            $result = Get-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns correct results" {
            $result.Schema -eq "dbo" | Should -Be $true
            $result.Name -eq "StartUpProc$random" | Should -Be $true
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.StoredProcedure"
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Schema",
                "ObjectId",
                "CreateDate",
                "DateLastModified",
                "Name",
                "ImplementationType",
                "Startup"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.Properties["ObjectId"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["ObjectId"].MemberType | Should -Be "AliasProperty"
        }
    }

    Context "When filtering by StartupProcedure parameter" {
        It "Returns correct results" {
            $result = Get-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSingle -StartupProcedure $startupProc
            $result.Schema -eq "dbo" | Should -Be $true
            $result.Name -eq "StartUpProc$random" | Should -Be $true
        }
    }

    Context "When filtering by incorrect StartupProcedure parameter" {
        It "Returns no results" {
            $result = Get-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSingle -StartupProcedure "Not.Here"
            $null -eq $result | Should -Be $true
        }
    }

}