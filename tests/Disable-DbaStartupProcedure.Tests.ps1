#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaStartupProcedure",
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
                "InputObject",
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

        # Set up test environment
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random
        $startupProcName = "StartUpProc$random"
        $startupProc = "dbo.$startupProcName"
        $dbname = "master"

        $null = $server.Query("CREATE PROCEDURE $startupProc AS Select 1", $dbname)
        $null = $server.Query("EXEC sp_procoption '$startupProc', 'startup', 'on'", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up test objects
        $null = $server.Query("DROP PROCEDURE $startupProc", $dbname)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When disabling a startup procedure" {
        BeforeAll {
            $splatDisable = @{
                SqlInstance      = $TestConfig.InstanceSingle
                StartupProcedure = $startupProc
            }
            $result = Disable-DbaStartupProcedure @splatDisable
        }

        It "Should return correct schema" {
            $result.Schema | Should -Be "dbo"
        }

        It "Should return correct procedure name" {
            $result.Name | Should -Be $startupProcName
        }

        It "Should show Disable action" {
            $result.Action | Should -Be "Disable"
        }

        It "Should report success status" {
            $result.Status | Should -Be $true
        }

        It "Should return success note" {
            $result.Note | Should -Be "Disable succeded"
        }
    }

    Context "When disabling an already disabled procedure" {
        BeforeAll {
            $splatDisableAgain = @{
                SqlInstance      = $TestConfig.InstanceSingle
                StartupProcedure = $startupProc
            }
            $result = Disable-DbaStartupProcedure @splatDisableAgain
        }

        It "Should return correct schema" {
            $result.Schema | Should -Be "dbo"
        }

        It "Should return correct procedure name" {
            $result.Name | Should -Be $startupProcName
        }

        It "Should show Disable action" {
            $result.Action | Should -Be "Disable"
        }

        It "Should report unchanged status" {
            $result.Status | Should -Be $false
        }

        It "Should return already performed note" {
            $result.Note | Should -Be "Action Disable already performed"
        }
    }

    Context "When using pipeline input" {
        BeforeAll {
            $splatEnable = @{
                SqlInstance      = $TestConfig.InstanceSingle
                StartupProcedure = $startupProc
            }
            $null = Enable-DbaStartupProcedure @splatEnable
            # TEST-SCOPING: pipe ONLY the fixture procedure. Unfiltered, this disabled every
            # startup procedure on the shared instance - including replication's
            # sp_MSrepl_startup - which both broke these single-object assertions (2 records)
            # and mutated state other suites depend on (measured gate red; the repl proc was
            # re-enabled by hand).
            $result = Get-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -eq $startupProcName | Disable-DbaStartupProcedure
        }

        It "Should return correct schema" {
            $result.Schema | Should -Be "dbo"
        }

        It "Should return correct procedure name" {
            $result.Name | Should -Be $startupProcName
        }

        It "Should show Disable action" {
            $result.Action | Should -Be "Disable"
        }

        It "Should report success status" {
            $result.Status | Should -Be $true
        }

        It "Should return success note" {
            $result.Note | Should -Be "Disable succeded"
        }
    }

    Context "When a trailing pipeline record has no input object" {
        BeforeAll {
            # Re-enable so the first record performs a real disable.
            $null = Enable-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSingle -StartupProcedure $startupProc -Confirm:$false
            $fixtureProc = Get-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -eq $startupProcName

            # The Add-Member/Select-DefaultView emit block sits OUTSIDE the inner foreach over the
            # input objects, so a record whose input is empty still emits - re-using the previous
            # record's stored-procedure variables. Piping the fixture procedure followed by $null
            # drives two records: the second (empty) record re-emits the first record's procedure.
            # A single-record leg cannot observe this cross-record behaviour.
            $crossRecordResult = $fixtureProc, $null | Disable-DbaStartupProcedure -Confirm:$false
        }

        It "Emits one object per record, including the empty trailing record" {
            @($crossRecordResult).Count | Should -Be 2
        }

        It "The empty trailing record re-emits the previous procedure" {
            @($crossRecordResult).Name | Should -Be @($startupProcName, $startupProcName)
        }
    }
}