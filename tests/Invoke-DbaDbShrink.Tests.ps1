#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbShrink",
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
                "ExcludeDatabase",
                "AllUserDatabases",
                "PercentFreeSpace",
                "ShrinkMethod",
                "FileType",
                "StepSize",
                "StatementTimeout",
                "ExcludeIndexStats",
                "ExcludeUpdateUsage",
                "EnableException",
                "InputObject"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $defaultPath = $server | Get-DbaDefaultPath

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying Database is shrunk" {
        BeforeEach {
            # Create Database with small size and grow it
            $db = New-Object Microsoft.SqlServer.Management.SMO.Database($server, "dbatoolsci_shrinktest")

            $primaryFileGroup = New-Object Microsoft.SqlServer.Management.Smo.Filegroup($db, "PRIMARY")
            $db.FileGroups.Add($primaryFileGroup)
            $primaryFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile($primaryFileGroup, $db.Name)
            $primaryFile.FileName = "$($defaultPath.Data)\$($db.Name).mdf"
            $primaryFile.Size = 8 * 1024
            $primaryFile.Growth = 8 * 1024
            $primaryFile.GrowthType = "KB"
            $primaryFileGroup.Files.Add($primaryFile)

            $logFile = New-Object Microsoft.SqlServer.Management.Smo.LogFile($db, "$($db.Name)_log")
            $logFile.FileName = "$($defaultPath.Log)\$($db.Name)_log.ldf"
            $logFile.Size = 8 * 1024
            $logFile.Growth = 8 * 1024
            $logFile.GrowthType = "KB"
            $db.LogFiles.Add($logFile)

            $db.Create()

            # grow the files
            $server.Query("
            ALTER DATABASE [$($db.name)] MODIFY FILE ( NAME = N'$($db.name)', SIZE = 16384KB )
            ALTER DATABASE [$($db.name)] MODIFY FILE ( NAME = N'$($db.name)_log', SIZE = 16384KB )")

            # Save the current file sizes
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $oldLogSize = $db.LogFiles[0].Size
            $oldDataSize = $db.FileGroups[0].Files[0].Size
            $db.Checkpoint()
        }
        AfterEach {
            $db | Remove-DbaDatabase
        }

        It "Shrinks just the log file when FileType is Log" {
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType Log
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be "$($db.Name)_log"
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -Be $oldDataSize
            $db.LogFiles[0].Size | Should -BeLessThan $oldLogSize
        }

        It "Shrinks just the data file(s) when FileType is Data" {
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType Data
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be $db.Name
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
            $db.LogFiles[0].Size | Should -Be $oldLogSize
        }

        It "Shrinks the entire database when FileType is All" {
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType All
            $result.Database | Should -Be $db.Name, $db.Name
            $result.File | Should -Be "$($db.Name)_log", $db.Name
            $result.Success | Should -Be $true, $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.LogFiles[0].Size | Should -BeLessThan $oldLogSize
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
        }

        It "Shrinks just the data file(s) when FileType is Data and uses the StepSize" {
            $result = Invoke-DbaDbShrink $server -Database $db.Name -FileType Data -StepSize 2MB
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be $db.Name
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
            $db.LogFiles[0].Size | Should -Be $oldLogSize
        }

        It "Accepts pipelined databases (see #9495)" {
            $result = $db | Invoke-DbaDbShrink -FileType Data
            $result.Database | Should -Be $db.Name
            $result.File | Should -Be $db.Name
            $result.Success | Should -Be $true
            $db.Refresh()
            $db.RecalculateSpaceUsage()
            $db.FileGroups[0].Files[0].Refresh()
            $db.LogFiles[0].Refresh()
            $db.FileGroups[0].Files[0].Size | Should -BeLessThan $oldDataSize
            $db.LogFiles[0].Size | Should -Be $oldLogSize
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputDb = New-Object Microsoft.SqlServer.Management.SMO.Database($server, "dbatoolsci_shrink_output")

            $primaryFileGroup = New-Object Microsoft.SqlServer.Management.Smo.Filegroup($outputDb, "PRIMARY")
            $outputDb.FileGroups.Add($primaryFileGroup)
            $primaryFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile($primaryFileGroup, $outputDb.Name)
            $primaryFile.FileName = "$($defaultPath.Data)\$($outputDb.Name).mdf"
            $primaryFile.Size = 8 * 1024
            $primaryFile.Growth = 8 * 1024
            $primaryFile.GrowthType = "KB"
            $primaryFileGroup.Files.Add($primaryFile)

            $logFile = New-Object Microsoft.SqlServer.Management.Smo.LogFile($outputDb, "$($outputDb.Name)_log")
            $logFile.FileName = "$($defaultPath.Log)\$($outputDb.Name)_log.ldf"
            $logFile.Size = 8 * 1024
            $logFile.Growth = 8 * 1024
            $logFile.GrowthType = "KB"
            $outputDb.LogFiles.Add($logFile)

            $outputDb.Create()

            $server.Query("
            ALTER DATABASE [$($outputDb.name)] MODIFY FILE ( NAME = N'$($outputDb.name)', SIZE = 16384KB )
            ALTER DATABASE [$($outputDb.name)] MODIFY FILE ( NAME = N'$($outputDb.name)_log', SIZE = 16384KB )")

            $outputDb.Refresh()
            $outputDb.Checkpoint()

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $outputResult = Invoke-DbaDbShrink $server -Database $outputDb.Name -FileType Data
        }

        AfterAll {
            $outputDb | Remove-DbaDatabase -ErrorAction SilentlyContinue -Confirm:$false
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected output properties" {
            $expectedProps = @(
                "ComputerName", "InstanceName", "SqlInstance", "Database", "File",
                "Start", "End", "Elapsed", "Success",
                "InitialSize", "InitialUsed", "InitialAvailable",
                "TargetAvailable", "FinalAvailable", "FinalSize",
                "InitialAverageFragmentation", "FinalAverageFragmentation",
                "InitialTopFragmentation", "FinalTopFragmentation", "Notes"
            )
            foreach ($prop in $expectedProps) {
                $outputResult[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present on the output object"
            }
        }

        It "Excludes fragmentation properties when using ExcludeIndexStats" {
            $excludedResult = Invoke-DbaDbShrink $server -Database $outputDb.Name -FileType Log -ExcludeIndexStats
            if (-not $excludedResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $excludedResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "InitialAverageFragmentation"
            $defaultProps | Should -Not -Contain "FinalAverageFragmentation"
            $defaultProps | Should -Not -Contain "InitialTopFragmentation"
            $defaultProps | Should -Not -Contain "FinalTopFragmentation"
        }
    }
}