param($ModuleName = 'dbatools')

Describe "Set-DbaTempDbConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $random = Get-Random

        $server = Connect-DbaInstance -SqlInstance $global:instance1

        $tempdbDataFilePhysicalName = $server.Databases['tempdb'].Query('SELECT physical_name as PhysicalName FROM sys.database_files WHERE file_id = 1').PhysicalName
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

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaTempDbConfig
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have DataFileCount as a parameter" {
            $CommandUnderTest | Should -HaveParameter DataFileCount -Type System.Int32
        }
        It "Should have DataFileSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter DataFileSize -Type System.Int32
        }
        It "Should have LogFileSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter LogFileSize -Type System.Int32
        }
        It "Should have DataFileGrowth as a parameter" {
            $CommandUnderTest | Should -HaveParameter DataFileGrowth -Type System.Int32
        }
        It "Should have LogFileGrowth as a parameter" {
            $CommandUnderTest | Should -HaveParameter LogFileGrowth -Type System.Int32
        }
        It "Should have DataPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter DataPath -Type System.String[]
        }
        It "Should have LogPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter LogPath -Type System.String
        }
        It "Should have OutFile as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutFile -Type System.String
        }
        It "Should have OutputScriptOnly as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutputScriptOnly -Type System.Management.Automation.SwitchParameter
        }
        It "Should have DisableGrowth as a parameter" {
            $CommandUnderTest | Should -HaveParameter DisableGrowth -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command actually works" {
        It "test with an invalid data dir" {
            $result = Set-DbaTempDbConfig -SqlInstance $global:instance1 -DataFileSize 1024 -DataPath "$tempdbDataFilePath\invalidDir_$random" -OutputScriptOnly
            $result | Should -BeNullOrEmpty
        }

        It "valid sql is produced with nearly all options set and a single data directory" {
            $result = Set-DbaTempDbConfig -SqlInstance $global:instance1 -DataFileCount 8 -DataFileSize 2048 -LogFileSize 512 -DataFileGrowth 1024 -LogFileGrowth 512 -DataPath "$tempdbDataFilePath\DataDir0_$random" -LogPath "$tempdbDataFilePath\Log_$random" -OutputScriptOnly
            $sqlStatements = $result -Split ";" | Where-Object { $_ -ne "" }

            $sqlStatements.Count | Should -Be 9
            ($sqlStatements | Where-Object { $_ -Match "size=256 MB,filegrowth=1024" -and $_ -Match "DataDir0_$random" }).Count | Should -Be 8
            ($sqlStatements | Where-Object { $_ -Match "size=512 MB,filegrowth=512" -and $_ -Match "Log_$random" }).Count | Should -Be 1
        }

        It "valid sql is produced with -DisableGrowth" {
            $result = Set-DbaTempDbConfig -SqlInstance $global:instance1 -DataFileCount 8 -DataFileSize 1024 -LogFileSize 512 -DisableGrowth -DataPath $tempdbDataFilePath -LogPath $tempdbDataFilePath -OutputScriptOnly
            $sqlStatements = $result -Split ";" | Where-Object { $_ -ne "" }

            $sqlStatements.Count | Should -Be 9
            ($sqlStatements | Where-Object { $_ -Match "size=128 MB,filegrowth=0" }).Count | Should -Be 8
            ($sqlStatements | Where-Object { $_ -Match "size=512 MB,filegrowth=0" -and $_ -Match "log" }).Count | Should -Be 1
        }

        It "multiple data directories are supported" {
            $dataDirLocations = "$tempdbDataFilePath\DataDir0_$random", "$tempdbDataFilePath\DataDir1_$random", "$tempdbDataFilePath\DataDir2_$random"
            $result = Set-DbaTempDbConfig -SqlInstance $global:instance1 -DataFileCount 8 -DataFileSize 1024 -DataPath $dataDirLocations -OutputScriptOnly
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
