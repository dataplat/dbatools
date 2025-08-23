#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaTempDbConfig",
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
                "DataFileCount",
                "DataFileSize",
                "LogFileSize",
                "DataFileGrowth",
                "LogFileGrowth",
                "DataPath",
                "LogPath",
                "OutFile",
                "OutputScriptOnly",
                "DisableGrowth",
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

        $random = Get-Random

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1

        $tempdbDataFilePhysicalName = $server.Databases["tempdb"].Query("SELECT physical_name as PhysicalName FROM sys.database_files WHERE file_id = 1").PhysicalName
        $tempdbDataFilePath = Split-Path $tempdbDataFilePhysicalName

        $null = New-Item -Path "$tempdbDataFilePath\DataDir0_$random" -Type Directory
        $null = New-Item -Path "$tempdbDataFilePath\DataDir1_$random" -Type Directory
        $null = New-Item -Path "$tempdbDataFilePath\DataDir2_$random" -Type Directory
        $null = New-Item -Path "$tempdbDataFilePath\Log_$random" -Type Directory

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created directories.
        Remove-Item -Path "$tempdbDataFilePath\DataDir0_$random" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$tempdbDataFilePath\DataDir1_$random" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$tempdbDataFilePath\DataDir2_$random" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$tempdbDataFilePath\Log_$random" -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Command actually works" {

        It "test with an invalid data dir" {
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.instance1 -DataFileSize 1024 -DataPath "$tempdbDataFilePath\invalidDir_$random" -OutputScriptOnly -WarningAction SilentlyContinue -WarningVariable WarnVar
            $WarnVar | Should -Match "does not exist"
            $result | Should -BeNullOrEmpty
        }

        It "valid sql is produced with nearly all options set and a single data directory" {
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.instance1 -DataFileCount 8 -DataFileSize 2048 -LogFileSize 512 -DataFileGrowth 1024 -LogFileGrowth 512 -DataPath "$tempdbDataFilePath\DataDir0_$random" -LogPath "$tempdbDataFilePath\Log_$random" -OutputScriptOnly -WarningAction SilentlyContinue
            $sqlStatements = $result -Split ";" | Where-Object { $PSItem -ne "" }

            $sqlStatements.Count | Should -Be 9
            ($sqlStatements | Where-Object { $PSItem -Match "size=256 MB,filegrowth=1024" -and $PSItem -Match "DataDir0_$random" }).Count | Should -Be 8
            ($sqlStatements | Where-Object { $PSItem -Match "size=512 MB,filegrowth=512" -and $PSItem -Match "Log_$random" }).Count | Should -Be 1
        }

        It "valid sql is produced with -DisableGrowth" {
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.instance1 -DataFileCount 8 -DataFileSize 1024 -LogFileSize 512 -DisableGrowth -DataPath $tempdbDataFilePath -LogPath $tempdbDataFilePath -OutputScriptOnly -WarningAction SilentlyContinue
            $sqlStatements = $result -Split ";" | Where-Object { $PSItem -ne "" }

            $sqlStatements.Count | Should -Be 9
            ($sqlStatements | Where-Object { $PSItem -Match "size=128 MB,filegrowth=0" }).Count | Should -Be 8
            ($sqlStatements | Where-Object { $PSItem -Match "size=512 MB,filegrowth=0" -and $PSItem -Match "log" }).Count | Should -Be 1
        }

        It "multiple data directories are supported" {
            $dataDirLocations = "$tempdbDataFilePath\DataDir0_$random", "$tempdbDataFilePath\DataDir1_$random", "$tempdbDataFilePath\DataDir2_$random"
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.instance1 -DataFileCount 8 -DataFileSize 1024 -DataPath $dataDirLocations -OutputScriptOnly -WarningAction SilentlyContinue
            $sqlStatements = $result -Split ";" | Where-Object { $PSItem -ne "" }

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