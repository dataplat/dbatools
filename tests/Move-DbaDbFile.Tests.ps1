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

        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name "dbatoolsci_MoveDbFile"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name "dbatoolsci_MoveDbFile_2DataFiles"

        $dbFiles = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_MoveDbFile_2DataFiles" | Where-Object TypeDescription -eq "ROWS"
        $physicalPathFolder = Split-Path -Path $dbFiles[0].PhysicalName -Parent
        $physicalPathNewFolder = "$physicalPathFolder\moveFile"
        if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
            $null = New-Item -Path $physicalPathNewFolder -Type Directory
        } else {
            Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock { $null = New-Item -Path $args[0] -Type Directory } -ArgumentList $physicalPathNewFolder
        }

        $addNewDataFile = @"
        ALTER DATABASE [dbatoolsci_MoveDbFile_2DataFiles]
        ADD FILE ( NAME = N'dbatoolsci_MoveDbFile_2DataFiles_2'
                , FILENAME = N'$physicalPathFolder\dbatoolsci_MoveDbFile_2DataFiles_2.ndf')
        TO FILEGROUP [PRIMARY]
        GO
"@
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $addNewDataFile

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_MoveDbFile", "dbatoolsci_MoveDbFile_2DataFiles"
        if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
            Remove-Item -Path "$physicalPathFolder\moveFile" -Recurse
            Remove-Item -Path "$physicalPathFolder\New" -Recurse
            Remove-Item -Path "$physicalPathFolder\dbatoolsci_MoveDbFile.mdf"
        } else {
            Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock {
                Remove-Item -Path "$($args[0])\moveFile" -Recurse
                Remove-Item -Path "$($args[0])\New" -Recurse
                Remove-Item -Path "$($args[0])\dbatoolsci_MoveDbFile.mdf"
            } -ArgumentList $physicalPathFolder
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Should output current database structure" {
        BeforeAll {
            $splatFileStructure = @{
                SqlInstance       = $TestConfig.InstanceSingle
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
            $dbDataFiles = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_MoveDbFile" | Where-Object TypeDescription -eq "ROWS"

            $splatMoveData = @{
                SqlInstance     = $TestConfig.InstanceSingle
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
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_MoveDbFile").Status | Should -Be "ONLINE"
        }
    }

    Context "Should move all database log files and delete source" {
        BeforeAll {
            $dbLogFiles = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_MoveDbFile" | Where-Object TypeDescription -eq "LOG"

            $splatMoveLog = @{
                SqlInstance     = $TestConfig.InstanceSingle
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
            if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
                Test-Path -Path $dbLogFiles.PhysicalName | Should -Be $false
            } else {
                Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock { Test-Path -Path $args[0] } -ArgumentList $dbLogFiles.PhysicalName -Raw | Should -Be $false
            }
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_MoveDbFile").Status | Should -Be "ONLINE"
        }
    }

    Context "Should move only one database file and delete source" {
        BeforeAll {
            $dbNDFFile = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_MoveDbFile_2DataFiles" | Where-Object LogicalName -eq "dbatoolsci_MoveDbFile_2DataFiles_2"

            $splatMoveSpecific = @{
                SqlInstance     = $TestConfig.InstanceSingle
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
            if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
                Test-Path -Path $dbNDFFile.PhysicalName | Should -Be $false
            } else {
                Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock { Test-Path -Path $args[0] } -ArgumentList $dbNDFFile.PhysicalName -Raw | Should -Be $false
            }
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_MoveDbFile_2DataFiles").Status | Should -Be "ONLINE"
        }
    }

    Context "Should move all files and delete source" {
        BeforeAll {
            $dbAllFiles = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_MoveDbFile_2DataFiles"

            $destinationFolder = "$physicalPathFolder\New"
            if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
                $null = New-Item -Path $destinationFolder -Type Directory
            } else {
                Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock { $null = New-Item -Path $args[0] -Type Directory } -ArgumentList $destinationFolder
            }

            $splatMoveAll = @{
                SqlInstance     = $TestConfig.InstanceSingle
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
                if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
                    Test-Path -Path $PSItem | Should -Be $false
                } else {
                    Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock { Test-Path -Path $args[0] } -ArgumentList $PSItem -Raw | Should -Be $false
                }
            }
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_MoveDbFile_2DataFiles").Status | Should -Be "ONLINE"
        }
    }

    Context "Output validation for FileStructureOnly" {
        BeforeAll {
            $splatStructure = @{
                SqlInstance       = $TestConfig.InstanceSingle
                Database          = "dbatoolsci_MoveDbFile_2DataFiles"
                FileStructureOnly = $true
            }
            $structureOutput = Move-DbaDbFile @splatStructure
        }

        It "Returns a string when using FileStructureOnly" {
            $structureOutput | Should -Not -BeNullOrEmpty
            $structureOutput | Should -BeOfType [string]
        }

        It "Contains the expected hashtable format" {
            $structureOutput | Should -BeLike "*fileToMove*"
        }
    }

}