$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'FileType', 'FileDestination', 'FileToMove', 'DeleteAfterMove', 'FileStructureOnly', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name 'dbatoolsci_MoveDbFile'
        $null = New-DbaDatabase -SqlInstance $script:instance2 -Name 'dbatoolsci_MoveDbFile_2DataFiles'

        $dbFiles = Get-DbaDbFile -SqlInstance $script:instance2 -Database dbatoolsci_MoveDbFile_2DataFiles | Where-Object TypeDescription -eq 'ROWS'
        $physicalPathFolder = Split-Path -Path $dbFiles[0].PhysicalName -Parent
        $physicalPathPreviousFolder = Split-Path -Path $physicalPathFolder -Parent

        $addNewDataFile = @"
        ALTER DATABASE [dbatoolsci_MoveDbFile_2DataFiles]
        ADD FILE ( NAME = N'dbatoolsci_MoveDbFile_2DataFiles_2'
                , FILENAME = N'$physicalPathFolder\dbatoolsci_MoveDbFile_2DataFiles_2.ndf')
        TO FILEGROUP [PRIMARY]
        GO
"@
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Query $addNewDataFile
    }
    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance2 -Database "dbatoolsci_MoveDbFile", "dbatoolsci_MoveDbFile_2DataFiles" -Confirm:$false
    }

    Context "Should output current database structure" {
        $variables = @{
            SqlInstance       = $script:instance2
            Database          = 'dbatoolsci_MoveDbFile'
            FileStructureOnly = $true
        }

        $results = Move-DbaDbFile @variables

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have a logical name" {
            $results | Should BeLike '*dbatoolsci_MoveDbFile*'
        }
        It "Should not have filename and/or extensions" {
            $results | Should Not BeLike '*mdf*'
        }
    }

    Context "Should move all database data files" {
        $dbDataFiles = Get-DbaDbFile -SqlInstance $script:instance2 -Database dbatoolsci_MoveDbFile | Where-Object TypeDescription -eq 'ROWS'

        $variables = @{
            SqlInstance     = $script:instance2
            Database        = 'dbatoolsci_MoveDbFile'
            FileType        = 'Data'
            FileDestination = $physicalPathPreviousFolder
        }

        $results = Move-DbaDbFile @variables -Verbose

        Start-Sleep -Seconds 5

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have a Success results" {
            $results.Result | Should Be 'Success'
        }
        It "Should have updated database metadata" {
            $results.DatabaseFileMetadata | Should Be 'Updated'
        }
        It "Should have the previous database name" {
            Test-Path -Path $dbDataFiles.PhysicalName | Should Be $true
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $script:instance2 -Database 'dbatoolsci_MoveDbFile').Status | Should Be 'ONLINE'
        }
    }

    Context "Should move all database log files and delete source" {
        $dbLogFiles = Get-DbaDbFile -SqlInstance $script:instance2 -Database dbatoolsci_MoveDbFile | Where-Object TypeDescription -eq 'LOG'

        $variables = @{
            SqlInstance     = $script:instance2
            Database        = 'dbatoolsci_MoveDbFile'
            FileType        = 'Log'
            FileDestination = $physicalPathPreviousFolder
            DeleteAfterMove = $true
        }

        $results = Move-DbaDbFile @variables

        Start-Sleep -Seconds 5

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have a Success results" {
            $results.Result | Should Be 'Success'
        }
        It "Should have updated database metadata" {
            $results.DatabaseFileMetadata | Should Be 'Updated'
        }
        It "Should have deleted source log file " {
            Test-Path -Path $dbLogFiles.PhysicalName | Should Be $false
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $script:instance2 -Database 'dbatoolsci_MoveDbFile').Status | Should Be 'ONLINE'
        }
    }

    Context "Should move only one database file and delete source" {
        $dbNDFFile = Get-DbaDbFile -SqlInstance $script:instance2 -Database dbatoolsci_MoveDbFile_2DataFiles | Where-Object LogicalName -eq 'dbatoolsci_MoveDbFile_2DataFiles_2'

        $variables = @{
            SqlInstance     = $script:instance2
            Database        = 'dbatoolsci_MoveDbFile_2DataFiles'
            FileToMove      = @{
                'dbatoolsci_MoveDbFile_2DataFiles_2' = $physicalPathPreviousFolder
            }
            DeleteAfterMove = $true
        }

        $results = Move-DbaDbFile @variables

        Start-Sleep -Seconds 5

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have a Success results" {
            $results.Result | Should Be 'Success'
        }
        It "Should have updated database metadata" {
            $results.DatabaseFileMetadata | Should Be 'Updated'
        }
        It "Should have deleted source NDF file " {
            Test-Path -Path $dbNDFFile.PhysicalName | Should Be $false
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $script:instance2 -Database 'dbatoolsci_MoveDbFile_2DataFiles').Status | Should Be 'ONLINE'
        }
    }

    Context "Should move all files and delete source" {
        $dbAllFiles = Get-DbaDbFile -SqlInstance $script:instance2 -Database dbatoolsci_MoveDbFile_2DataFiles

        $destinationFolder = "$physicalPathFolder\New"
        $null = New-Item -Path $destinationFolder -Type Directory

        $variables = @{
            SqlInstance     = $script:instance2
            Database        = 'dbatoolsci_MoveDbFile_2DataFiles'
            FileType        = 'Both'
            FileDestination = $destinationFolder
            DeleteAfterMove = $true
        }

        $results = Move-DbaDbFile @variables

        Start-Sleep -Seconds 5

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have a Success results" {
            $results.Result | foreach-object {
                $_ | Should Be 'Success'
            }
        }
        It "Should have updated database metadata" {
            $results.DatabaseFileMetadata | foreach-object {
                $_ | Should Be 'Updated'
            }
        }
        It "Should have deleted source files" {
            $dbAllFiles.PhysicalName | foreach-object {
                Test-Path -Path $_ | Should Be $false
            }
        }
        It "Should have database Online" {
            (Get-DbaDbState -SqlInstance $script:instance2 -Database 'dbatoolsci_MoveDbFile_2DataFiles').Status | Should Be 'ONLINE'
        }
    }
}