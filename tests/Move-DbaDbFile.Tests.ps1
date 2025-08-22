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
        $global:physicalPathFolder = Split-Path -Path $dbFiles[0].PhysicalName -Parent
        $global:physicalPathNewFolder = "$global:physicalPathFolder\moveFile"
        $null = New-Item -Path $global:physicalPathNewFolder -Type Directory

        $addNewDataFile = @"
        ALTER DATABASE [dbatoolsci_MoveDbFile_2DataFiles]
        ADD FILE ( NAME = N'dbatoolsci_MoveDbFile_2DataFiles_2'
                , FILENAME = N'$global:physicalPathFolder\dbatoolsci_MoveDbFile_2DataFiles_2.ndf')
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
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile", "dbatoolsci_MoveDbFile_2DataFiles" -Confirm:$false
        Remove-Item -Path "$global:physicalPathFolder\moveFile" -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path "$global:physicalPathFolder\New" -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path "$global:physicalPathFolder\dbatoolsci_MoveDbFile.mdf" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Should output current database structure" {
        BeforeAll {
            $splatFileStructure = @{
                SqlInstance       = $TestConfig.instance2
                Database          = "dbatoolsci_MoveDbFile"
                FileStructureOnly = $true
            }

            $global:structureResults = Move-DbaDbFile @splatFileStructure
        }

        It "Should have Results" {
            $global:structureResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a logical name" {
            $global:structureResults | Should -BeLike "*dbatoolsci_MoveDbFile*"
        }
        It "Should not have filename and/or extensions" {
            $global:structureResults | Should -Not -BeLike "*mdf*"
        }
    }

    Context "Should move all database data files" {
        BeforeAll {
            $global:dbDataFiles = Get-DbaDbFile -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile" | Where-Object TypeDescription -eq "ROWS"

            $splatMoveData = @{
                SqlInstance     = $TestConfig.instance2
                Database        = "dbatoolsci_MoveDbFile"
                FileType        = "Data"
                FileDestination = $global:physicalPathNewFolder
            }

            $global:dataResults = Move-DbaDbFile @splatMoveData

            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $global:dataResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $global:dataResults.Result | Should -Be "Success"
        }
        It "Should have updated database metadata" {
            $global:dataResults.DatabaseFileMetadata | Should -Be "Updated"
        }
        It "Should have the previous database name" {
            Test-Path -Path $global:dbDataFiles.PhysicalName | Should -Be $true
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile").Status | Should -Be "ONLINE"
        }
    }

    Context "Should move all database log files and delete source" {
        BeforeAll {
            $global:dbLogFiles = Get-DbaDbFile -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile" | Where-Object TypeDescription -eq "LOG"

            $splatMoveLog = @{
                SqlInstance     = $TestConfig.instance2
                Database        = "dbatoolsci_MoveDbFile"
                FileType        = "Log"
                FileDestination = $global:physicalPathNewFolder
                DeleteAfterMove = $true
            }

            $global:logResults = Move-DbaDbFile @splatMoveLog

            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $global:logResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $global:logResults.Result | Should -Be "Success"
        }
        It "Should have updated database metadata" {
            $global:logResults.DatabaseFileMetadata | Should -Be "Updated"
        }
        It "Should have deleted source log file " {
            Test-Path -Path $global:dbLogFiles.PhysicalName | Should -Be $false
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile").Status | Should -Be "ONLINE"
        }
    }

    Context "Should move only one database file and delete source" {
        BeforeAll {
            $global:dbNDFFile = Get-DbaDbFile -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile_2DataFiles" | Where-Object LogicalName -eq "dbatoolsci_MoveDbFile_2DataFiles_2"

            $splatMoveSpecific = @{
                SqlInstance     = $TestConfig.instance2
                Database        = "dbatoolsci_MoveDbFile_2DataFiles"
                FileToMove      = @{
                    "dbatoolsci_MoveDbFile_2DataFiles_2" = $global:physicalPathNewFolder
                }
                DeleteAfterMove = $true
            }

            $global:specificResults = Move-DbaDbFile @splatMoveSpecific

            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $global:specificResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $global:specificResults.Result | Should -Be "Success"
        }
        It "Should have updated database metadata" {
            $global:specificResults.DatabaseFileMetadata | Should -Be "Updated"
        }
        It "Should have deleted source NDF file " {
            Test-Path -Path $global:dbNDFFile.PhysicalName | Should -Be $false
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile_2DataFiles").Status | Should -Be "ONLINE"
        }
    }

    Context "Should move all files and delete source" {
        BeforeAll {
            $global:dbAllFiles = Get-DbaDbFile -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile_2DataFiles"

            $global:destinationFolder = "$global:physicalPathFolder\New"
            $null = New-Item -Path $global:destinationFolder -Type Directory

            $splatMoveAll = @{
                SqlInstance     = $TestConfig.instance2
                Database        = "dbatoolsci_MoveDbFile_2DataFiles"
                FileType        = "Both"
                FileDestination = $global:destinationFolder
                DeleteAfterMove = $true
            }

            $global:allResults = Move-DbaDbFile @splatMoveAll

            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $global:allResults | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $global:allResults.Result | ForEach-Object {
                $PSItem | Should -Be "Success"
            }
        }
        It "Should have updated database metadata" {
            $global:allResults.DatabaseFileMetadata | ForEach-Object {
                $PSItem | Should -Be "Updated"
            }
        }
        It "Should have deleted source files" {
            $global:dbAllFiles.PhysicalName | ForEach-Object {
                Test-Path -Path $PSItem | Should -Be $false
            }
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_MoveDbFile_2DataFiles").Status | Should -Be "ONLINE"
        }
    }
}