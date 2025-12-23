#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDacPackage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "OutputPath",
                "DacVersion",
                "DacDescription",
                "DatabaseName",
                "Recursive",
                "SqlServerVersion",
                "Filter",
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

        # Create a temporary directory for test files
        $testFolder = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $testFolder -ItemType Directory -Force

        # Create a subdirectory for SQL source files
        $sqlSourcePath = "$testFolder\Schema"
        $null = New-Item -Path $sqlSourcePath -ItemType Directory -Force

        # Create subdirectories for organized SQL files
        $tablesPath = "$sqlSourcePath\Tables"
        $viewsPath = "$sqlSourcePath\Views"
        $null = New-Item -Path $tablesPath -ItemType Directory -Force
        $null = New-Item -Path $viewsPath -ItemType Directory -Force

        # Create test SQL files
        $table1Sql = @"
CREATE TABLE dbo.TestTable1 (
    Id INT NOT NULL PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    CreatedDate DATETIME2 NOT NULL DEFAULT GETDATE()
);
"@

        $table2Sql = @"
CREATE TABLE dbo.TestTable2 (
    Id INT NOT NULL PRIMARY KEY,
    TestTable1Id INT NOT NULL,
    Description NVARCHAR(500) NULL,
    CONSTRAINT FK_TestTable2_TestTable1 FOREIGN KEY (TestTable1Id) REFERENCES dbo.TestTable1(Id)
);
"@

        $viewSql = @"
CREATE VIEW dbo.TestView
AS
SELECT
    t1.Id,
    t1.Name,
    t2.Description
FROM dbo.TestTable1 t1
LEFT JOIN dbo.TestTable2 t2 ON t1.Id = t2.TestTable1Id;
"@

        # Write the SQL files
        Set-Content -Path "$tablesPath\TestTable1.sql" -Value $table1Sql -Encoding UTF8
        Set-Content -Path "$tablesPath\TestTable2.sql" -Value $table2Sql -Encoding UTF8
        Set-Content -Path "$viewsPath\TestView.sql" -Value $viewSql -Encoding UTF8

        # Create an empty SQL file for edge case testing
        Set-Content -Path "$sqlSourcePath\EmptyFile.sql" -Value "" -Encoding UTF8

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up the test folder
        Remove-Item -Path $testFolder -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Build DACPAC from SQL files" {
        It "Builds a DACPAC from a directory with SQL files recursively" {
            $outputDacpac = "$testFolder\output-recursive.dacpac"
            $splatBuildRecursive = @{
                Path          = $sqlSourcePath
                OutputPath    = $outputDacpac
                Recursive     = $true
                DatabaseName  = "TestDatabase"
                WarningAction = "SilentlyContinue"
            }
            $result = New-DbaDacPackage @splatBuildRecursive

            $WarnVar | Should -BeLike "*Skipping empty file: *\Schema\EmptyFile.sql"
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -BeTrue
            $result.Path | Should -Be $outputDacpac
            $result.DatabaseName | Should -Be "TestDatabase"
            $result.FileCount | Should -BeGreaterThan 0
            $result.ObjectCount | Should -BeGreaterThan 0
            Test-Path $outputDacpac | Should -BeTrue
        }

        It "Builds a DACPAC with custom version and description" {
            $outputDacpac = "$testFolder\output-versioned.dacpac"
            $splatBuildVersioned = @{
                Path           = $sqlSourcePath
                OutputPath     = $outputDacpac
                Recursive      = $true
                DatabaseName   = "VersionedDB"
                DacVersion     = "2.1.0.0"
                DacDescription = "Test DACPAC with version"
                WarningAction  = "SilentlyContinue"
            }
            $result = New-DbaDacPackage @splatBuildVersioned

            $WarnVar | Should -BeLike "*Skipping empty file: *\Schema\EmptyFile.sql"
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -BeTrue
            $result.Version | Should -Be "2.1.0.0"
            Test-Path $outputDacpac | Should -BeTrue
        }

        It "Uses SQL Server version targeting" {
            $outputDacpac = "$testFolder\output-sql2017.dacpac"
            $splatBuildTargeted = @{
                Path             = $sqlSourcePath
                OutputPath       = $outputDacpac
                Recursive        = $true
                DatabaseName     = "Sql2017DB"
                SqlServerVersion = "Sql140"
                WarningAction    = "SilentlyContinue"
            }
            $result = New-DbaDacPackage @splatBuildTargeted

            $WarnVar | Should -BeLike "*Skipping empty file: *\Schema\EmptyFile.sql"
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -BeTrue
            Test-Path $outputDacpac | Should -BeTrue
        }

        It "Builds from non-recursive directory scan" {
            $outputDacpac = "$testFolder\output-nonrecursive.dacpac"
            $splatBuildNonRecursive = @{
                Path          = $sqlSourcePath
                OutputPath    = $outputDacpac
                DatabaseName  = "NonRecursiveDB"
                WarningAction = "SilentlyContinue"
            }
            $result = New-DbaDacPackage @splatBuildNonRecursive

            # Non-recursive should only find the EmptyFile.sql in the root
            $WarnVar | Should -BeLike "*Skipping empty file: *\Schema\EmptyFile.sql"
            $result | Should -Not -BeNullOrEmpty
            # May succeed or fail depending on if there are valid SQL files in root
        }
    }

    Context "Output is pipeline-compatible with Publish-DbaDacPackage" {
        It "Returns object with Path property for pipeline compatibility" {
            $outputDacpac = "$testFolder\output-pipeline.dacpac"
            $splatBuildPipeline = @{
                Path          = $sqlSourcePath
                OutputPath    = $outputDacpac
                Recursive     = $true
                DatabaseName  = "PipelineDB"
                WarningAction = "SilentlyContinue"
            }
            $result = New-DbaDacPackage @splatBuildPipeline

            $WarnVar | Should -BeLike "*Skipping empty file: *\Schema\EmptyFile.sql"
            $result | Should -Not -BeNullOrEmpty
            $result.Path | Should -Not -BeNullOrEmpty
            $result.Database | Should -Not -BeNullOrEmpty
        }
    }

    Context "Error handling" {
        It "Handles non-existent path gracefully" {
            { New-DbaDacPackage -Path "$testFolder\NonExistentPath" -OutputPath "$testFolder\should-not-exist.dacpac" -EnableException } | Should -Throw
        }

        It "Handles empty directory gracefully" {
            $emptyDir = "$testFolder\EmptyDir"
            $null = New-Item -Path $emptyDir -ItemType Directory -Force

            { New-DbaDacPackage -Path $emptyDir -OutputPath "$testFolder\should-not-exist-empty.dacpac" -EnableException } | Should -Throw
        }
    }

    Context "Deploy built DACPAC" {
        It "Built DACPAC can be loaded by DacFx" {
            $outputDacpac = "$testFolder\output-loadtest.dacpac"
            $splatBuildLoadTest = @{
                Path          = $sqlSourcePath
                OutputPath    = $outputDacpac
                Recursive     = $true
                DatabaseName  = "LoadTestDB"
                WarningAction = "SilentlyContinue"
            }
            $result = New-DbaDacPackage @splatBuildLoadTest

            $WarnVar | Should -BeLike "*Skipping empty file: *\Schema\EmptyFile.sql"
            $result.Success | Should -BeTrue

            # Verify the DACPAC can be loaded
            $dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($outputDacpac)
            $dacPackage | Should -Not -BeNullOrEmpty
            $dacPackage.Name | Should -Be "LoadTestDB"
        }
    }
}
