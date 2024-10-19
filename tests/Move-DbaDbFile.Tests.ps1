param($ModuleName = 'dbatools')

Describe "Move-DbaDbFile" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        # Setup code
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name 'dbatoolsci_MoveDbFile'
        $null = New-DbaDatabase -SqlInstance $global:instance2 -Name 'dbatoolsci_MoveDbFile_2DataFiles'

        $dbFiles = Get-DbaDbFile -SqlInstance $global:instance2 -Database dbatoolsci_MoveDbFile_2DataFiles | Where-Object TypeDescription -eq 'ROWS'
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
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Query $addNewDataFile
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $global:instance2 -Database "dbatoolsci_MoveDbFile", "dbatoolsci_MoveDbFile_2DataFiles" -Confirm:$false
        Get-Item -Path "$physicalPathFolder\moveFile" | Remove-Item -Recurse
        Get-Item -Path "$physicalPathFolder\New" | Remove-Item -Recurse
        Get-Item -Path "$physicalPathFolder\dbatoolsci_MoveDbFile.mdf" | Remove-Item
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Move-DbaDbFile
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have FileType as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileType
        }
        It "Should have FileDestination as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileDestination
        }
        It "Should have FileToMove as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileToMove
        }
        It "Should have DeleteAfterMove as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DeleteAfterMove
        }
        It "Should have FileStructureOnly as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter FileStructureOnly
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Should output current database structure" {
        BeforeAll {
            $variables = @{
                SqlInstance       = $global:instance2
                Database          = 'dbatoolsci_MoveDbFile'
                FileStructureOnly = $true
            }

            $results = Move-DbaDbFile @variables
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have a logical name" {
            $results | Should -BeLike '*dbatoolsci_MoveDbFile*'
        }
        It "Should not have filename and/or extensions" {
            $results | Should -Not -BeLike '*mdf*'
        }
    }

    Context "Should move all database data files" {
        BeforeAll {
            $dbDataFiles = Get-DbaDbFile -SqlInstance $global:instance2 -Database dbatoolsci_MoveDbFile | Where-Object TypeDescription -eq 'ROWS'

            $variables = @{
                SqlInstance     = $global:instance2
                Database        = 'dbatoolsci_MoveDbFile'
                FileType        = 'Data'
                FileDestination = $physicalPathNewFolder
            }

            $results = Move-DbaDbFile @variables

            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $results.Result | Should -Be 'Success'
        }
        It "Should have updated database metadata" {
            $results.DatabaseFileMetadata | Should -Be 'Updated'
        }
        It "Should have the previous database name" {
            Test-Path -Path $dbDataFiles.PhysicalName | Should -Be $true
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $global:instance2 -Database 'dbatoolsci_MoveDbFile').Status | Should -Be 'ONLINE'
        }
    }

    Context "Should move all database log files and delete source" {
        BeforeAll {
            $dbLogFiles = Get-DbaDbFile -SqlInstance $global:instance2 -Database dbatoolsci_MoveDbFile | Where-Object TypeDescription -eq 'LOG'

            $variables = @{
                SqlInstance     = $global:instance2
                Database        = 'dbatoolsci_MoveDbFile'
                FileType        = 'Log'
                FileDestination = $physicalPathNewFolder
                DeleteAfterMove = $true
            }

            $results = Move-DbaDbFile @variables

            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $results.Result | Should -Be 'Success'
        }
        It "Should have updated database metadata" {
            $results.DatabaseFileMetadata | Should -Be 'Updated'
        }
        It "Should have deleted source log file " {
            Test-Path -Path $dbLogFiles.PhysicalName | Should -Be $false
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $global:instance2 -Database 'dbatoolsci_MoveDbFile').Status | Should -Be 'ONLINE'
        }
    }

    Context "Should move only one database file and delete source" {
        BeforeAll {
            $dbNDFFile = Get-DbaDbFile -SqlInstance $global:instance2 -Database dbatoolsci_MoveDbFile_2DataFiles | Where-Object LogicalName -eq 'dbatoolsci_MoveDbFile_2DataFiles_2'

            $variables = @{
                SqlInstance     = $global:instance2
                Database        = 'dbatoolsci_MoveDbFile_2DataFiles'
                FileToMove      = @{
                    'dbatoolsci_MoveDbFile_2DataFiles_2' = $physicalPathNewFolder
                }
                DeleteAfterMove = $true
            }

            $results = Move-DbaDbFile @variables

            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $results.Result | Should -Be 'Success'
        }
        It "Should have updated database metadata" {
            $results.DatabaseFileMetadata | Should -Be 'Updated'
        }
        It "Should have deleted source NDF file " {
            Test-Path -Path $dbNDFFile.PhysicalName | Should -Be $false
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $global:instance2 -Database 'dbatoolsci_MoveDbFile_2DataFiles').Status | Should -Be 'ONLINE'
        }
    }

    Context "Should move all files and delete source" {
        BeforeAll {
            $dbAllFiles = Get-DbaDbFile -SqlInstance $global:instance2 -Database dbatoolsci_MoveDbFile_2DataFiles

            $destinationFolder = "$physicalPathFolder\New"
            $null = New-Item -Path $destinationFolder -Type Directory

            $variables = @{
                SqlInstance     = $global:instance2
                Database        = 'dbatoolsci_MoveDbFile_2DataFiles'
                FileType        = 'Both'
                FileDestination = $destinationFolder
                DeleteAfterMove = $true
            }

            $results = Move-DbaDbFile @variables

            Start-Sleep -Seconds 5
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have a Success results" {
            $results.Result | ForEach-Object {
                $_ | Should -Be 'Success'
            }
        }
        It "Should have updated database metadata" {
            $results.DatabaseFileMetadata | ForEach-Object {
                $_ | Should -Be 'Updated'
            }
        }
        It "Should have deleted source files" {
            $dbAllFiles.PhysicalName | ForEach-Object {
                Test-Path -Path $_ | Should -Be $false
            }
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $global:instance2 -Database 'dbatoolsci_MoveDbFile_2DataFiles').Status | Should -Be 'ONLINE'
        }
    }
}
