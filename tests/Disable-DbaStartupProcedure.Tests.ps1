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
            $result = Get-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSingle | Disable-DbaStartupProcedure
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

    Context "Output Validation" {
        BeforeAll {
            $splatEnableForOutput = @{
                SqlInstance      = $TestConfig.InstanceSingle
                StartupProcedure = $startupProc
            }
            $null = Enable-DbaStartupProcedure @splatEnableForOutput
            $result = Disable-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSingle -StartupProcedure $startupProc -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.StoredProcedure]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'Schema',
                'Name',
                'Startup',
                'Action',
                'Status',
                'Note'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has dbatools-added properties" {
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Database | Should -Not -BeNullOrEmpty
            $result.Action | Should -Be "Disable"
            $result.Status | Should -BeIn @($true, $false)
            $result.Note | Should -Not -BeNullOrEmpty
        }

        It "Has Startup property set to false after disable" {
            $result.Startup | Should -Be $false
        }
    }
}