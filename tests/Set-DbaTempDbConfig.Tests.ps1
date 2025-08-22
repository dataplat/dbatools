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

        $global:random = Get-Random

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1

        $tempdbDataFilePhysicalName = $server.Databases["tempdb"].Query("SELECT physical_name as PhysicalName FROM sys.database_files WHERE file_id = 1").PhysicalName
        $global:tempdbDataFilePath = Split-Path $tempdbDataFilePhysicalName

        $null = New-Item -Path "$global:tempdbDataFilePath\DataDir0_$global:random" -Type Directory
        $null = New-Item -Path "$global:tempdbDataFilePath\DataDir1_$global:random" -Type Directory
        $null = New-Item -Path "$global:tempdbDataFilePath\DataDir2_$global:random" -Type Directory
        $null = New-Item -Path "$global:tempdbDataFilePath\Log_$global:random" -Type Directory

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created directories.
        Remove-Item -Path "$global:tempdbDataFilePath\DataDir0_$global:random" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$global:tempdbDataFilePath\DataDir1_$global:random" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$global:tempdbDataFilePath\DataDir2_$global:random" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$global:tempdbDataFilePath\Log_$global:random" -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Command actually works" {

        It "test with an invalid data dir" {
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.instance1 -DataFileSize 1024 -DataPath "$global:tempdbDataFilePath\invalidDir_$global:random" -OutputScriptOnly -WarningAction SilentlyContinue -WarningVariable WarnVar
            $WarnVar | Should -Match "does not exist"
            $result | Should -BeNullOrEmpty
        }

        It "valid sql is produced with nearly all options set and a single data directory" {
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.instance1 -DataFileCount 8 -DataFileSize 2048 -LogFileSize 512 -DataFileGrowth 1024 -LogFileGrowth 512 -DataPath "$global:tempdbDataFilePath\DataDir0_$global:random" -LogPath "$global:tempdbDataFilePath\Log_$global:random" -OutputScriptOnly -WarningAction SilentlyContinue
            $sqlStatements = $result -Split ";" | Where-Object { $PSItem -ne "" }

            $sqlStatements.Count | Should -Be 9
            ($sqlStatements | Where-Object { $PSItem -Match "size=256 MB,filegrowth=1024" -and $PSItem -Match "DataDir0_$global:random" }).Count | Should -Be 8
            ($sqlStatements | Where-Object { $PSItem -Match "size=512 MB,filegrowth=512" -and $PSItem -Match "Log_$global:random" }).Count | Should -Be 1
        }

        It "valid sql is produced with -DisableGrowth" {
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.instance1 -DataFileCount 8 -DataFileSize 1024 -LogFileSize 512 -DisableGrowth -DataPath $global:tempdbDataFilePath -LogPath $global:tempdbDataFilePath -OutputScriptOnly -WarningAction SilentlyContinue
            $sqlStatements = $result -Split ";" | Where-Object { $PSItem -ne "" }

            $sqlStatements.Count | Should -Be 9
            ($sqlStatements | Where-Object { $PSItem -Match "size=128 MB,filegrowth=0" }).Count | Should -Be 8
            ($sqlStatements | Where-Object { $PSItem -Match "size=512 MB,filegrowth=0" -and $PSItem -Match "log" }).Count | Should -Be 1
        }

        It "multiple data directories are supported" {
            $dataDirLocations = "$global:tempdbDataFilePath\DataDir0_$global:random", "$global:tempdbDataFilePath\DataDir1_$global:random", "$global:tempdbDataFilePath\DataDir2_$global:random"
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