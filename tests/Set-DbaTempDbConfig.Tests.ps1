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
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Reducing the tempdb data file count" {
            BeforeEach {
                $tempdbFiles = @(
                    [PSCustomObject]@{
                        FileId       = 1
                        LogicalName  = "tempdev"
                        PhysicalName = "C:\tempdb\tempdb.mdf"
                        SizeMb       = 256
                        UsedMb       = 10
                    },
                    [PSCustomObject]@{
                        FileId       = 2
                        LogicalName  = "temp2"
                        PhysicalName = "C:\tempdb\temp2.ndf"
                        SizeMb       = 256
                        UsedMb       = 10
                    },
                    [PSCustomObject]@{
                        FileId       = 3
                        LogicalName  = "temp3"
                        PhysicalName = "C:\tempdb\temp3.ndf"
                        SizeMb       = 256
                        UsedMb       = 10
                    },
                    [PSCustomObject]@{
                        FileId       = 4
                        LogicalName  = "temp4"
                        PhysicalName = "C:\tempdb\temp4.ndf"
                        SizeMb       = 256
                        UsedMb       = 10
                    }
                )
                $tempdb = [PSCustomObject]@{
                    FileMetadata = $tempdbFiles
                }
                $tempdb | Add-Member -MemberType ScriptMethod -Name Query -Value {
                    param($Query)

                    if ($Query -match "FILEPROPERTY") {
                        return $this.FileMetadata
                    }
                    if ($Query -match "file_id = 1") {
                        return [PSCustomObject]@{
                            PhysicalName = "C:\tempdb\tempdb.mdf"
                        }
                    }
                    if ($Query -match "file_id = 2") {
                        return [PSCustomObject]@{
                            PhysicalName = "C:\tempdb\templog.ldf"
                        }
                    }
                    if ($Query -match "COUNT") {
                        return [PSCustomObject]@{
                            FileCount = $this.FileMetadata.Count
                        }
                    }
                    return $null
                }
                $master = [PSCustomObject]@{
                    ExecutedQuery = $null
                }
                $master | Add-Member -MemberType ScriptMethod -Name ExecuteNonQuery -Value {
                    param($Query)
                    $this.ExecutedQuery = $Query
                }
                $script:mockTempdbServer = [PSCustomObject]@{
                    ComputerName       = "sql1"
                    ServiceName        = "MSSQLSERVER"
                    DomainInstanceName = "sql1"
                    Processors         = 4
                    Databases          = @{
                        tempdb = $tempdb
                        master = $master
                    }
                }

                Mock Connect-DbaInstance {
                    $script:mockTempdbServer
                }
                Mock Get-DbaDbFile -RemoveParameterType "SqlInstance" {
                    @(
                        [PSCustomObject]@{
                            Type         = 0
                            ID           = 1
                            LogicalName  = "tempdev"
                            PhysicalName = "C:\tempdb\tempdb.mdf"
                        },
                        [PSCustomObject]@{
                            Type         = 0
                            ID           = 2
                            LogicalName  = "temp2"
                            PhysicalName = "C:\tempdb\temp2.ndf"
                        },
                        [PSCustomObject]@{
                            Type         = 0
                            ID           = 3
                            LogicalName  = "temp3"
                            PhysicalName = "C:\tempdb\temp3.ndf"
                        },
                        [PSCustomObject]@{
                            Type         = 0
                            ID           = 4
                            LogicalName  = "temp4"
                            PhysicalName = "C:\tempdb\temp4.ndf"
                        },
                        [PSCustomObject]@{
                            Type         = 1
                            ID           = 5
                            LogicalName  = "templog"
                            PhysicalName = "C:\tempdb\templog.ldf"
                            Size         = [PSCustomObject]@{
                                Megabyte = 256
                            }
                        }
                    )
                }
                Mock Stop-Function {
                    param($Message)
                    throw $Message
                }
            }

            It "retains the existing refusal without Force" {
                { Set-DbaTempDbConfig -SqlInstance "sql1" -DataFileCount 2 -DataFileSize 512 -OutputScriptOnly } | Should -Throw "*greater number of files*"
            }

            It "evacuates and removes the highest secondary file ids first with Force" {
                $script:mockTempdbServer.Databases.tempdb.FileMetadata[0].UsedMb = 482
                $result = Set-DbaTempDbConfig -SqlInstance "sql1" -DataFileCount 2 -DataFileSize 512 -Force -OutputScriptOnly

                $shrinkStatements = @($result | Where-Object { $PSItem -match "DBCC SHRINKFILE" })
                $removalStatements = @($result | Where-Object { $PSItem -match "DBCC SHRINKFILE|FILEPROPERTY" })
                $firstModifyIndex = [array]::IndexOf($result, ($result | Where-Object { $PSItem -match "MODIFY FILE" } | Select-Object -First 1))
                $firstShrinkIndex = [array]::IndexOf($result, $shrinkStatements[0])

                $shrinkStatements.Count | Should -Be 2
                $shrinkStatements[0] | Should -Match "N'temp4', EMPTYFILE"
                $shrinkStatements[1] | Should -Match "N'temp3', EMPTYFILE"
                $removalStatements | Should -Match "^USE \[tempdb\];"
                $firstModifyIndex | Should -BeLessThan $firstShrinkIndex
                ($result -join "`n") | Should -Not -Match "REMOVE FILE \[tempdev\]"

                $null = Set-DbaTempDbConfig -SqlInstance "sql1" -DataFileCount 2 -DataFileSize 512 -Force -Confirm:$false
                $script:mockTempdbServer.Databases.master.ExecutedQuery | Should -Be $result
            }

            It "refuses forced reduction when used space exceeds target capacity" {
                $script:mockTempdbServer.Databases.tempdb.FileMetadata[0].UsedMb = 500

                { Set-DbaTempDbConfig -SqlInstance "sql1" -DataFileCount 2 -DataFileSize 512 -Force -OutputScriptOnly } | Should -Throw "*exceeds the requested target capacity*"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        $tempdbDataFilePhysicalName = $server.Databases["tempdb"].Query("SELECT physical_name as PhysicalName FROM sys.database_files WHERE file_id = 1").PhysicalName
        $tempdbDataFilePath = Split-Path $tempdbDataFilePhysicalName

        if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
            $null = New-Item -Path "$tempdbDataFilePath\DataDir0_$random" -Type Directory
            $null = New-Item -Path "$tempdbDataFilePath\DataDir1_$random" -Type Directory
            $null = New-Item -Path "$tempdbDataFilePath\DataDir2_$random" -Type Directory
            $null = New-Item -Path "$tempdbDataFilePath\Log_$random" -Type Directory
        } else {
            Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock {
                $null = New-Item -Path "$($args[0])\DataDir0_$($args[1])" -Type Directory
                $null = New-Item -Path "$($args[0])\DataDir1_$($args[1])" -Type Directory
                $null = New-Item -Path "$($args[0])\DataDir2_$($args[1])" -Type Directory
                $null = New-Item -Path "$($args[0])\Log_$($args[1])" -Type Directory
            } -ArgumentList $tempdbDataFilePath, $random
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created directories.
        if (([DbaInstanceParameter]($TestConfig.InstanceSingle)).IsLocalHost) {
            Remove-Item -Path "$tempdbDataFilePath\DataDir0_$random" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$tempdbDataFilePath\DataDir1_$random" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$tempdbDataFilePath\DataDir2_$random" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$tempdbDataFilePath\Log_$random" -Force -ErrorAction SilentlyContinue
        } else {
            Invoke-Command2 -ComputerName $TestConfig.InstanceSingle -ScriptBlock {
                Remove-Item -Path "$($args[0])\DataDir0_$($args[1])" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$($args[0])\DataDir1_$($args[1])" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$($args[0])\DataDir2_$($args[1])" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$($args[0])\Log_$($args[1])" -Force -ErrorAction SilentlyContinue
            } -ArgumentList $tempdbDataFilePath, $random
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Command actually works" {

        It "test with an invalid data dir" {
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.InstanceSingle -DataFileSize 1024 -DataPath "$tempdbDataFilePath\invalidDir_$random" -OutputScriptOnly -WarningAction SilentlyContinue -WarningVariable WarnVar
            $WarnVar | Should -Match "does not exist"
            $result | Should -BeNullOrEmpty
        }

        It "valid sql is produced with nearly all options set and a single data directory" {
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.InstanceSingle -DataFileCount 8 -DataFileSize 2048 -LogFileSize 512 -DataFileGrowth 1024 -LogFileGrowth 512 -DataPath "$tempdbDataFilePath\DataDir0_$random" -LogPath "$tempdbDataFilePath\Log_$random" -OutputScriptOnly -WarningAction SilentlyContinue
            $sqlStatements = $result -Split ";" | Where-Object { $PSItem -ne "" }

            $sqlStatements.Count | Should -Be 9
            ($sqlStatements | Where-Object { $PSItem -Match "size=256 MB,filegrowth=1024" -and $PSItem -Match "DataDir0_$random" }).Count | Should -Be 8
            ($sqlStatements | Where-Object { $PSItem -Match "size=512 MB,filegrowth=512" -and $PSItem -Match "Log_$random" }).Count | Should -Be 1
        }

        It "valid sql is produced with -DisableGrowth" {
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.InstanceSingle -DataFileCount 8 -DataFileSize 1024 -LogFileSize 512 -DisableGrowth -DataPath $tempdbDataFilePath -LogPath $tempdbDataFilePath -OutputScriptOnly -WarningAction SilentlyContinue
            $sqlStatements = $result -Split ";" | Where-Object { $PSItem -ne "" }

            $sqlStatements.Count | Should -Be 9
            ($sqlStatements | Where-Object { $PSItem -Match "size=128 MB,filegrowth=0" }).Count | Should -Be 8
            ($sqlStatements | Where-Object { $PSItem -Match "size=512 MB,filegrowth=0" -and $PSItem -Match "log" }).Count | Should -Be 1
        }

        It "multiple data directories are supported" {
            $dataDirLocations = "$tempdbDataFilePath\DataDir0_$random", "$tempdbDataFilePath\DataDir1_$random", "$tempdbDataFilePath\DataDir2_$random"
            $result = Set-DbaTempDbConfig -SqlInstance $TestConfig.InstanceSingle -DataFileCount 8 -DataFileSize 1024 -DataPath $dataDirLocations -OutputScriptOnly -WarningAction SilentlyContinue
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
