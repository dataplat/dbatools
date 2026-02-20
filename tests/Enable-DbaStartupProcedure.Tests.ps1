#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaStartupProcedure",
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

        # Set variables. They are available in all the It blocks.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random
        $startupProcName = "StartUpProc$random"
        $startupProc = "dbo.$startupProcName"
        $dbname = "master"

        # Create the test startup procedure
        $null = $server.Query("CREATE PROCEDURE $startupProc AS Select 1", $dbname)
        # Ensure startup is off regardless of prior state (e.g. CI retries)
        $null = $server.Query("EXEC sp_procoption '$startupProc', 'startup', 'off'", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = $server.Query("DROP PROCEDURE $startupProc", $dbname)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When enabling a startup procedure" {
        BeforeAll {
            $splatEnable = @{
                SqlInstance      = $TestConfig.InstanceSingle
                StartupProcedure = $startupProc
            }
            $result = Enable-DbaStartupProcedure @splatEnable
        }

        It "Should return successful enable results" {
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Enable"
            $result.Status | Should -Be $true
            $result.Note | Should -Be "Enable succeded"
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result.psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.StoredProcedure"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "Startup", "Action", "Status", "Note")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected property values for a successful enable" {
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Database | Should -Be "master"
            $result.Startup | Should -BeTrue
            $result.Action | Should -Be "Enable"
            $result.Status | Should -BeTrue
        }
    }

    Context "When enabling an already enabled procedure" {
        BeforeAll {
            $splatAlreadyEnabled = @{
                SqlInstance      = $TestConfig.InstanceSingle
                StartupProcedure = $startupProc
            }
            $result = Enable-DbaStartupProcedure @splatAlreadyEnabled
        }

        It "Should return already enabled status" {
            $result.Schema | Should -Be "dbo"
            $result.Name | Should -Be $startupProcName
            $result.Action | Should -Be "Enable"
            $result.Status | Should -Be $false
            $result.Note | Should -Be "Action Enable already performed"
        }
    }

    Context "When enabling a non-existent procedure" {
        BeforeAll {
            $splatNonExistent = @{
                SqlInstance      = $TestConfig.InstanceSingle
                StartupProcedure = "Unknown.NotHere"
                WarningVariable  = "warn"
                WarningAction    = "SilentlyContinue"
            }
            $result = Enable-DbaStartupProcedure @splatNonExistent
        }

        It "Should return null" {
            $result | Should -BeNull
        }
        It "Should warn that procedure does not exist" {
            $warn | Should -Match "Requested procedure Unknown.NotHere does not exist"
        }
    }

    Context "When using an invalid procedure name format" {
        BeforeAll {
            $splatInvalidFormat = @{
                SqlInstance      = $TestConfig.InstanceSingle
                StartupProcedure = "Four.Part.Schema.Name"
                WarningVariable  = "warn"
                WarningAction    = "SilentlyContinue"
            }
            $result = Enable-DbaStartupProcedure @splatInvalidFormat
        }

        It "Should return null" {
            $result | Should -BeNull
        }
        It "Should warn that procedure name could not be parsed" {
            $warn | Should -Match "Requested procedure Four.Part.Schema.Name could not be parsed"
        }
    }
}