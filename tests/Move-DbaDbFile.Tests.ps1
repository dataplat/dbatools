#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Move-DbaDbFile",
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
                "FileType",
                "FileDestination",
                "FileToMove",
                "DeleteAfterMove",
                "FileStructureOnly",
                "Force",
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
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile", "dbatoolsci_MoveDbFile_2DataFiles"
        Remove-Item -Path "$physicalPathFolder\moveFile" -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path "$physicalPathFolder\New" -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path "$physicalPathFolder\dbatoolsci_MoveDbFile.mdf" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Should output current database structure" {
        BeforeAll {
            $splatFileStructure = @{
                SqlInstance       = $TestConfig.instance2
                Database          = "dbatoolsci_MoveDbFile"
                FileStructureOnly = $true
            }

            $structureResults = Move-DbaDbFile @splatFileStructure
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

            $splatMoveData = @{
                SqlInstance     = $TestConfig.instance2
                Database        = "dbatoolsci_MoveDbFile"
                FileType        = "Data"
                FileDestination = $physicalPathNewFolder
            }

            $dataResults = Move-DbaDbFile @splatMoveData

            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $dataResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $dataResults.Result | Should -Be "Success"
        }
        It "Should have updated database metadata" {
            $dataResults.DatabaseFileMetadata | Should -Be "Updated"
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

            $splatMoveLog = @{
                SqlInstance     = $TestConfig.instance2
                Database        = "dbatoolsci_MoveDbFile"
                FileType        = "Log"
                FileDestination = $physicalPathNewFolder
                DeleteAfterMove = $true
            }

            $logResults = Move-DbaDbFile @splatMoveLog

            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $logResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $logResults.Result | Should -Be "Success"
        }
        It "Should have updated database metadata" {
            $logResults.DatabaseFileMetadata | Should -Be "Updated"
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

            $splatMoveSpecific = @{
                SqlInstance     = $TestConfig.instance2
                Database        = "dbatoolsci_MoveDbFile_2DataFiles"
                FileToMove      = @{
                    "dbatoolsci_MoveDbFile_2DataFiles_2" = $physicalPathNewFolder
                }
                DeleteAfterMove = $true
            }

            $specificResults = Move-DbaDbFile @splatMoveSpecific

            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $specificResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $specificResults.Result | Should -Be "Success"
        }
        It "Should have updated database metadata" {
            $specificResults.DatabaseFileMetadata | Should -Be "Updated"
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

            $splatMoveAll = @{
                SqlInstance     = $TestConfig.instance2
                Database        = "dbatoolsci_MoveDbFile_2DataFiles"
                FileType        = "Both"
                FileDestination = $destinationFolder
                DeleteAfterMove = $true
            }

            $allResults = Move-DbaDbFile @splatMoveAll

            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $allResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $allResults.Result | ForEach-Object {
                $PSItem | Should -Be "Success"
            }
        }
        It "Should have updated database metadata" {
            $allResults.DatabaseFileMetadata | ForEach-Object {
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