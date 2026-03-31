#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaDbSchema",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SourcePath",
                "TargetSqlInstance",
                "TargetSqlCredential",
                "TargetDatabase",
                "TargetPath",
                "OutputPath",
                "KeepReport",
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

        # Install SqlPackage if needed.
        $null = Install-DbaSqlPackage

        # Create a temp directory for exports and reports.
        $testFolder = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $testFolder -ItemType Directory

        $random = Get-Random
        $dbSourceName = "dbatoolsci_schema_source_$random"
        $dbTargetName = "dbatoolsci_schema_target_$random"

        # Create source DB with a table.
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbSourceName
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbSourceName -Query "CREATE TABLE dbo.SourceOnly (id int PRIMARY KEY)"

        # Create target DB (empty - no tables, so source will show Create differences).
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbTargetName

        # Define file paths for the DACPACs.
        $sourceDacpac = "$testFolder\$dbSourceName.dacpac"
        $emptyTargetDacpac = "$testFolder\$dbTargetName.dacpac"

        # Export source DB to a DACPAC.
        $splatExport = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $dbSourceName
            FilePath    = $sourceDacpac
        }
        $null = Export-DbaDacPackage @splatExport

        # Export the empty target DB to a DACPAC now, before any tests modify it.
        $splatExportTarget = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $dbTargetName
            FilePath    = $emptyTargetDacpac
        }
        $null = Export-DbaDacPackage @splatExportTarget

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbSourceName, $dbTargetName -Confirm:$false

        Remove-Item -Path $testFolder -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Compare DACPAC against a live database" {
        It "Returns schema differences when source has objects not in target" {
            $splatCompare = @{
                SourcePath        = $sourceDacpac
                TargetSqlInstance = $TestConfig.InstanceSingle
                TargetDatabase    = $dbTargetName
                OutputPath        = $testFolder
            }
            $result = Compare-DbaDbSchema @splatCompare
            $result | Should -Not -BeNullOrEmpty
            $result.Operation | Should -Contain "Create"
            $result.Type | Should -Contain "Table"
        }

        It "Returns no differences when source and target are identical" {
            # Deploy the DACPAC to target first so they match.
            $splatPublish = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbTargetName
                Path        = $sourceDacpac
            }
            $null = Publish-DbaDacPackage @splatPublish

            $splatCompare = @{
                SourcePath        = $sourceDacpac
                TargetSqlInstance = $TestConfig.InstanceSingle
                TargetDatabase    = $dbTargetName
                OutputPath        = $testFolder
            }
            $result = Compare-DbaDbSchema @splatCompare
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Compare two DACPAC files" {
        It "Returns schema differences between two DACPAC files" {
            $splatCompare = @{
                SourcePath = $sourceDacpac
                TargetPath = $emptyTargetDacpac
                OutputPath = $testFolder
            }
            $result = Compare-DbaDbSchema @splatCompare
            $result | Should -Not -BeNullOrEmpty
            $result[0].SourcePath | Should -Be (Resolve-Path -Path $sourceDacpac).Path
            $result[0].Target | Should -Be $emptyTargetDacpac
        }

        It "Keeps the report file when -KeepReport is specified" {
            $splatCompare = @{
                SourcePath = $sourceDacpac
                TargetPath = $emptyTargetDacpac
                OutputPath = $testFolder
                KeepReport = $true
            }
            $result = Compare-DbaDbSchema @splatCompare
            $result | Should -Not -BeNullOrEmpty
            $result[0].ReportPath | Should -Not -BeNullOrEmpty
            Test-Path -Path $result[0].ReportPath | Should -BeTrue
        }
    }
}
