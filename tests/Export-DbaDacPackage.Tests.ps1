#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaDacPackage",
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
                "AllUserDatabases",
                "Path",
                "FilePath",
                "DacOption",
                "ExtendedParameters",
                "ExtendedProperties",
                "Type",
                "Table",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Check if SqlPackage is available, skip tests if not found
        $sqlPackagePath = Get-DbaSqlPackagePath
        if (-not $sqlPackagePath) {
            Write-Warning "SqlPackage.exe not found. Attempting to install..."
            try {
                Install-DbaSqlPackage -ErrorAction Stop
                $sqlPackagePath = Get-DbaSqlPackagePath
                if (-not $sqlPackagePath) {
                    throw "SqlPackage installation failed"
                }
                Write-Host "SqlPackage installed successfully" -ForegroundColor Green
            } catch {
                Write-Warning "Could not install SqlPackage. Tests will be skipped. Error: $_"
                return
            }
        } else {
            Write-Host "SqlPackage found at: $sqlPackagePath" -ForegroundColor Green
        }

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $testFolder = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"

        $random = Get-Random
        $dbname = "dbatoolsci_exportdacpac_$random"
        try {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $null = $server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname
            $null = $db.Query("CREATE TABLE dbo.example (id int, PRIMARY KEY (id));
            INSERT dbo.example
            SELECT top 100 object_id
            FROM sys.objects")
        } catch { } # No idea why appveyor can't handle this

        $dbName2 = "dbatoolsci:2_$random"
        $dbName2Escaped = "dbatoolsci`$2_$random"

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbName2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created object.
        $splatRemoveDb = @{
            SqlInstance = $TestConfig.instance1
            Database    = $dbname, $dbName2
            Confirm     = $false
        }
        Remove-DbaDatabase @splatRemoveDb

        # Remove the backup directory.
        Remove-Item -Path $testFolder -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    # See https://github.com/dataplat/dbatools/issues/7038
    Context "Ensure the database name is part of the generated filename" {
        It "Database name is included in the output filename" {
            $result = Export-DbaDacPackage -SqlInstance $TestConfig.instance1 -Database $dbname
            $result.Path | Should -BeLike "*$($dbName)*"
        }

        It "Database names with invalid filesystem chars are successfully exported" {
            $result = Export-DbaDacPackage -SqlInstance $TestConfig.instance1 -Database $dbname, $dbName2
            $result.Path.Count | Should -BeExactly 2
            $result.Path[0] | Should -BeLike "*$($dbName)*"
            $result.Path[1] | Should -BeLike "*$($dbName2Escaped)*"
        }
    }

    Context "Extract dacpac" {
        BeforeEach {
            $currentTestFolder = "$testFolder\dacpac-$(Get-Random)"
            New-Item $currentTestFolder -ItemType Directory -Force
            Push-Location $currentTestFolder
        }

        AfterEach {
            Pop-Location
            Remove-Item $currentTestFolder -Force -Recurse -ErrorAction SilentlyContinue
        }

        BeforeAll {
            $tableExists = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $dbname -Table example
        }

        It "exports a dacpac" -Skip:(-not $tableExists) {
            # Sometimes appveyor bombs
            $results = Export-DbaDacPackage -SqlInstance $TestConfig.instance1 -Database $dbname
            $results.Path | Should -Not -BeNullOrEmpty
            Test-Path $results.Path | Should -BeTrue
            if (($results).Path) {
                Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
            }
        }

        It "exports to the correct directory" -Skip:(-not $tableExists) {
            $relativePath = ".\"
            $expectedPath = (Resolve-Path $relativePath).Path
            $results = Export-DbaDacPackage -SqlInstance $TestConfig.instance1 -Database $dbname -Path $relativePath
            $results.Path | Split-Path | Should -Be $expectedPath
            Test-Path $results.Path | Should -BeTrue
        }

        It "exports dacpac with a table list" -Skip:(-not $tableExists) {
            $relativePath = ".\extract.dacpac"
            $expectedPath = Join-Path (Get-Item .) "extract.dacpac"
            $splatExportTable = @{
                SqlInstance = $TestConfig.instance1
                Database    = $dbname
                FilePath    = $relativePath
                Table       = "example"
            }
            $results = Export-DbaDacPackage @splatExportTable
            $results.Path | Should -Be $expectedPath
            Test-Path $results.Path | Should -BeTrue
            if (($results).Path) {
                Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
            }
        }

        It "uses EXE to extract dacpac" -Skip:(-not $tableExists) {
            $exportProperties = "/p:ExtractAllTableData=True"
            $splatExportExtended = @{
                SqlInstance        = $TestConfig.instance1
                Database           = $dbname
                ExtendedProperties = $exportProperties
            }
            $results = Export-DbaDacPackage @splatExportExtended
            $results.Path | Should -Not -BeNullOrEmpty
            Test-Path $results.Path | Should -BeTrue
            if (($results).Path) {
                Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Extract bacpac" {
        BeforeEach {
            $currentTestFolder = "$testFolder\bacpac-$(Get-Random)"
            New-Item $currentTestFolder -ItemType Directory -Force
            Push-Location $currentTestFolder
        }

        AfterEach {
            Pop-Location
            Remove-Item $currentTestFolder -Force -Recurse -ErrorAction SilentlyContinue
        }

        BeforeAll {
            $tableExists = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $dbname -Table example
        }

        It "exports a bacpac" -Skip:(-not $tableExists) {
            # Sometimes appveyor bombs
            $results = Export-DbaDacPackage -SqlInstance $TestConfig.instance1 -Database $dbname -Type Bacpac
            $results.Path | Should -Not -BeNullOrEmpty
            Test-Path $results.Path | Should -BeTrue
            if (($results).Path) {
                Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
            }
        }

        It "exports bacpac with a table list" -Skip:(-not $tableExists) {
            $relativePath = ".\extract.bacpac"
            $expectedPath = Join-Path (Get-Item .) "extract.bacpac"
            $splatExportBacpac = @{
                SqlInstance = $TestConfig.instance1
                Database    = $dbname
                FilePath    = $relativePath
                Table       = "example"
                Type        = "Bacpac"
            }
            $results = Export-DbaDacPackage @splatExportBacpac
            $results.Path | Should -Be $expectedPath
            Test-Path $results.Path | Should -BeTrue
            if (($results).Path) {
                Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
            }
        }

        It "uses EXE to extract bacpac" -Skip:(-not $tableExists) {
            $exportProperties = "/p:TargetEngineVersion=Default"
            $splatExportBacpacExt = @{
                SqlInstance        = $TestConfig.instance1
                Database           = $dbname
                ExtendedProperties = $exportProperties
                Type               = "Bacpac"
            }
            $results = Export-DbaDacPackage @splatExportBacpacExt
            $results.Path | Should -Not -BeNullOrEmpty
            Test-Path $results.Path | Should -BeTrue
            if (($results).Path) {
                Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
            }
        }
    }
}