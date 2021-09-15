$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'DataFileCount', 'DataFileSize', 'LogFileSize', 'DataFileGrowth', 'LogFileGrowth', 'DataPath', 'LogPath', 'OutFile', 'OutputScriptOnly', 'DisableGrowth', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random

        $instance1 = Connect-DbaInstance -SqlInstance $script:instance1

        $tempdbDataFilePhysicalName = $instance1.Databases['tempdb'].Query('SELECT physical_name as PhysicalName FROM sys.database_files WHERE file_id = 1').PhysicalName
        $tempdbDataFilePath = Split-Path $tempdbDataFilePhysicalName

        $null = New-Item -Path "$tempdbDataFilePath\DataDir0_$random" -Type Directory
        $null = New-Item -Path "$tempdbDataFilePath\DataDir1_$random" -Type Directory
        $null = New-Item -Path "$tempdbDataFilePath\DataDir2_$random" -Type Directory
        $null = New-Item -Path "$tempdbDataFilePath\Log_$random" -Type Directory
    }

    AfterAll {
        $null = Remove-Item "$tempdbDataFilePath\DataDir0_$random" -Force
        $null = Remove-Item "$tempdbDataFilePath\DataDir1_$random" -Force
        $null = Remove-Item "$tempdbDataFilePath\DataDir2_$random" -Force
        $null = Remove-Item "$tempdbDataFilePath\Log_$random" -Force
    }
    Context "Command actually works" {

        It "test with an invalid data dir" {
            $result = Set-DbaTempDbConfig -SqlInstance $instance1 -DataFileSize 1024 -DataPath "$tempdbDataFilePath\invalidDir_$random" -OutputScriptOnly
            $result | Should -BeNullOrEmpty
        }

        It "valid sql is produced with nearly all options set and a single data directory" {
            $result = Set-DbaTempDbConfig -SqlInstance $instance1 -DataFileCount 4 -DataFileSize 1024 -LogFileSize 512 -DataFileGrowth 1024 -LogFileGrowth 512 -DataPath "$tempdbDataFilePath\DataDir0_$random" -LogPath "$tempdbDataFilePath\Log_$random" -OutputScriptOnly
            $sqlStatements = $result -Split ";" | Where-Object { $_ -ne "" }

            $sqlStatements.Count | Should -Be 5
            ($sqlStatements | Where-Object { $_ -Match "size=256 MB,filegrowth=1024" -and $_ -Match "DataDir0_$random" }).Count | Should -Be 4
            ($sqlStatements | Where-Object { $_ -Match "size=512 MB,filegrowth=512" -and $_ -Match "Log_$random" }).Count | Should -Be 1
        }

        It "valid sql is produced with -DisableGrowth" {
            $result = Set-DbaTempDbConfig -SqlInstance $instance1 -DataFileCount 8 -DataFileSize 1024 -LogFileSize 512 -DisableGrowth -DataPath $tempdbDataFilePath -LogPath $tempdbDataFilePath -OutputScriptOnly
            $sqlStatements = $result -Split ";" | Where-Object { $_ -ne "" }

            $sqlStatements.Count | Should -Be 9
            ($sqlStatements | Where-Object { $_ -Match "size=128 MB,filegrowth=0" }).Count | Should -Be 8
            ($sqlStatements | Where-Object { $_ -Match "size=512 MB,filegrowth=0" -and $_ -Match "log" }).Count | Should -Be 1
        }

        It "multiple data directories are supported" {
            $dataDirLocations = "$tempdbDataFilePath\DataDir0_$random", "$tempdbDataFilePath\DataDir1_$random", "$tempdbDataFilePath\DataDir2_$random"
            $result = Set-DbaTempDbConfig -SqlInstance $instance1 -DataFileCount 8 -DataFileSize 1024 -DataPath $dataDirLocations -OutputScriptOnly
            $sqlStatements = $result -Split ";" | Where-Object { $_ -ne "" }

            # check the round robin assignment of files to data dir locations
            $indexToUse = 0
            foreach ($sqlStatement in $sqlStatements) {
                ($sqlStatement -Match "DataDir$indexToUse" -or $sqlStatement -Match "log") | Should -Be $true

                $indexToUse += 1
                if ($indexToUse -ge $dataDirLocations.Count) {
                    $indexToUse = 0
                }
            }
        }
    }
}