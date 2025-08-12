#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Move-DbaDbFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "FileType",
                "FileDestination",
                "FileToMove",
                "DeleteAfterMove",
                "FileStructureOnly",
                "Force",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name "dbatoolsci_MoveDbFile"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name "dbatoolsci_MoveDbFile_2DataFiles"

        $dbFiles = Get-DbaDbFile -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile_2DataFiles" | Where-Object TypeDescription -eq "ROWS"
        $physicalPathFolder = Split-Path -Path $dbFiles[0].PhysicalName -Parent
        $physicalPathNewFolder = "$physicalPathFolder\moveFile"
        $null = New-Item -Path $physicalPathNewFolder -Type Directory

        $addNewDataFile = @"
        ALTER DATABASE [dbatoolsci_MoveDbFile_2DataFiles]
        ADD FILE ( NAME = N'dbatoolsci_MoveDbFile_2DataFiles_2'
                , FILENAME = N'$physicalPathFolder\dbatoolsci_MoveDbFile_2DataFiles_2.ndf')
        TO FILEGROUP [PRIMARY]
        GO
"@
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query $addNewDataFile

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile", "dbatoolsci_MoveDbFile_2DataFiles" -Confirm:$false
        Remove-Item -Path "$physicalPathFolder\moveFile" -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path "$physicalPathFolder\New" -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path "$physicalPathFolder\dbatoolsci_MoveDbFile.mdf" -ErrorAction SilentlyContinue
    }

    Context "Should output current database structure" {
        BeforeAll {
            $splatStructure = @{
                SqlInstance       = $TestConfig.instance2
                Database          = "dbatoolsci_MoveDbFile"
                FileStructureOnly = $true
            }
            $structureResults = Move-DbaDbFile @splatStructure
        }

        It "Should have Results" {
            $structureResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a logical name" {
            $structureResults | Should -BeLike "*dbatoolsci_MoveDbFile*"
        }
        It "Should not have filename and/or extensions" {
            $structureResults | Should -Not -BeLike "*mdf*"
        }
    }

    Context "Should move all database data files" {
        BeforeAll {
            $dbDataFiles = Get-DbaDbFile -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile" | Where-Object TypeDescription -eq "ROWS"

            $splatDataFiles = @{
                SqlInstance     = $TestConfig.instance2
                Database        = "dbatoolsci_MoveDbFile"
                FileType        = "Data"
                FileDestination = $physicalPathNewFolder
            }
            $dataFilesResults = Move-DbaDbFile @splatDataFiles
            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $dataFilesResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $dataFilesResults.Result | Should -Be "Success"
        }
        It "Should have updated database metadata" {
            $dataFilesResults.DatabaseFileMetadata | Should -Be "Updated"
        }
        It "Should have the previous database name" {
            Test-Path -Path $dbDataFiles.PhysicalName | Should -Be $true
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile").Status | Should -Be "ONLINE"
        }
    }

    Context "Should move all database log files and delete source" {
        BeforeAll {
            $dbLogFiles = Get-DbaDbFile -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile" | Where-Object TypeDescription -eq "LOG"

            $splatLogFiles = @{
                SqlInstance     = $TestConfig.instance2
                Database        = "dbatoolsci_MoveDbFile"
                FileType        = "Log"
                FileDestination = $physicalPathNewFolder
                DeleteAfterMove = $true
            }
            $logFilesResults = Move-DbaDbFile @splatLogFiles
            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $logFilesResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $logFilesResults.Result | Should -Be "Success"
        }
        It "Should have updated database metadata" {
            $logFilesResults.DatabaseFileMetadata | Should -Be "Updated"
        }
        It "Should have deleted source log file " {
            Test-Path -Path $dbLogFiles.PhysicalName | Should -Be $false
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile").Status | Should -Be "ONLINE"
        }
    }

    Context "Should move only one database file and delete source" {
        BeforeAll {
            $dbNDFFile = Get-DbaDbFile -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile_2DataFiles" | Where-Object LogicalName -eq "dbatoolsci_MoveDbFile_2DataFiles_2"

            $splatSingleFile = @{
                SqlInstance     = $TestConfig.instance2
                Database        = "dbatoolsci_MoveDbFile_2DataFiles"
                FileToMove      = @{
                    "dbatoolsci_MoveDbFile_2DataFiles_2" = $physicalPathNewFolder
                }
                DeleteAfterMove = $true
            }
            $singleFileResults = Move-DbaDbFile @splatSingleFile
            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $singleFileResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $singleFileResults.Result | Should -Be "Success"
        }
        It "Should have updated database metadata" {
            $singleFileResults.DatabaseFileMetadata | Should -Be "Updated"
        }
        It "Should have deleted source NDF file " {
            Test-Path -Path $dbNDFFile.PhysicalName | Should -Be $false
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile_2DataFiles").Status | Should -Be "ONLINE"
        }
    }

    Context "Should move all files and delete source" {
        BeforeAll {
            $dbAllFiles = Get-DbaDbFile -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile_2DataFiles"

            $destinationFolder = "$physicalPathFolder\New"
            $null = New-Item -Path $destinationFolder -Type Directory

            $splatAllFiles = @{
                SqlInstance     = $TestConfig.instance2
                Database        = "dbatoolsci_MoveDbFile_2DataFiles"
                FileType        = "Both"
                FileDestination = $destinationFolder
                DeleteAfterMove = $true
            }
            $allFilesResults = Move-DbaDbFile @splatAllFiles
            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $allFilesResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $allFilesResults.Result | ForEach-Object {
                $PSItem | Should -Be "Success"
            }
        }
        It "Should have updated database metadata" {
            $allFilesResults.DatabaseFileMetadata | ForEach-Object {
                $PSItem | Should -Be "Updated"
            }
        }
        It "Should have deleted source files" {
            $dbAllFiles.PhysicalName | ForEach-Object {
                Test-Path -Path $PSItem | Should -Be $false
            }
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile_2DataFiles").Status | Should -Be "ONLINE"
        }
    }
}