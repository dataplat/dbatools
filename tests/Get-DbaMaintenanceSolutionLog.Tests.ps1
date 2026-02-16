#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaMaintenanceSolutionLog",
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
                "LogType",
                "Since",
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $logPath = $server.ErrorLogPath
        $uncPath = Join-AdminUnc -Servername $server.ComputerName -Filepath $logPath

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $testFileName = "IndexOptimize_$timestamp.txt"
        $testFilePath = Join-Path $uncPath $testFileName

        # Build a realistic IndexOptimize log file
        # Note: separator lines use a single space so ReadLine returns truthy values
        $splatLog = @(
            "Procedure: IndexOptimize"
            "Mode: SMART"
            "Execute: Y"
            " "
            "Database: [TestDB]"
            "Date and time: 2026-02-17 08:00:00"
            "Is accessible: Yes"
            "User access: MULTI_USER"
            "Standby: No"
            "Recovery Model: FULL"
            "Updateability: READ_WRITE"
            " "
            "Command: ALTER INDEX [IX_Test1] ON [TestDB].[dbo].[TestTable] REBUILD WITH (SORT_IN_TEMPDB=ON,ONLINE=ON,RESUMABLE=ON)"
            "Comment: ObjectType: U, IndexType: NonClusteredIndex, ImageText: No, NewLOB: No, FileStream: No, ColumnStore: No, AllowPageLocks: Yes, PageCount: 1000, Fragmentation: 35.5"
            "Date and time: 2026-02-17 08:00:00"
            "Duration: 00:00:05"
            "Date and time: 2026-02-17 08:00:05"
            " "
        )
        $logContent = ($splatLog -join "`r`n") + "`r`n"
        [System.IO.File]::WriteAllText($testFilePath, $logContent)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        Remove-Item -Path $testFilePath -Force -ErrorAction SilentlyContinue
    }

    Context "When parsing IndexOptimize log files" {
        BeforeAll {
            $global:dbatoolsciOutput = @(Get-DbaMaintenanceSolutionLog -SqlInstance $TestConfig.instance1 -OutVariable "global:dbatoolsciOutput")
        }

        It "Should return results from the log file" {
            $global:dbatoolsciOutput | Should -Not -BeNullOrEmpty
        }

        It "Should parse the database name correctly" {
            $global:dbatoolsciOutput[0].Database | Should -Be "TestDB"
        }

        It "Should parse the index name correctly" {
            $global:dbatoolsciOutput[0].Index | Should -Be "IX_Test1"
        }

        It "Should parse the action correctly" {
            $global:dbatoolsciOutput[0].Action | Should -Be "REBUILD"
        }

        It "Should parse the schema correctly" {
            $global:dbatoolsciOutput[0].Schema | Should -Be "dbo"
        }

        It "Should parse the table correctly" {
            $global:dbatoolsciOutput[0].Table | Should -Be "TestTable"
        }

        It "Should parse the fragmentation from the comment" {
            $global:dbatoolsciOutput[0].Fragmentation | Should -Be "35.5"
        }

        It "Should parse the duration as a timespan" {
            $global:dbatoolsciOutput[0].Duration | Should -BeOfType [timespan]
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "Action",
                "AllowPageLocks",
                "ColumnStore",
                "Comment",
                "Database",
                "Duration",
                "Error",
                "FileStream",
                "Fragmentation",
                "ImageText",
                "Index",
                "IndexType",
                "NewLOB",
                "ObjectType",
                "Options",
                "PageCount",
                "Partition",
                "Schema",
                "StartTime",
                "Statistics",
                "Table",
                "Timeout"
            )
            $actualProperties = ($global:dbatoolsciOutput[0].PSObject.Properties.Name | Sort-Object)
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
