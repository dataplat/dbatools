#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaDbTableData",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "InputObject",
                "ScriptingOptionsObject",
                "Path",
                "FilePath",
                "Encoding",
                "BatchSeparator",
                "NoPrefix",
                "Passthru",
                "NoClobber",
                "Append",
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

        # Set up test database connection and test tables
        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example (id int);
            INSERT dbo.dbatoolsci_example
            SELECT top 10 1
            FROM sys.objects")
        $null = $db.Query("Select * into dbatoolsci_temp from sys.databases")

        # For all the exported files that we want to clean up after the test, we create a directory that we can delete at the end.
        $exportPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $exportPath -ItemType Directory

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup test tables
        try {
            $null = $db.Query("DROP TABLE dbo.dbatoolsci_example")
            $null = $db.Query("DROP TABLE dbo.dbatoolsci_temp")
        } catch {
            $null = 1
        }

        # Remove the export directory.
        Remove-Item -Path $exportPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When exporting table data" {
        It "exports the table data" {
            $escaped = [regex]::escape("INSERT [dbo].[dbatoolsci_example] ([id]) VALUES (1)")
            $secondescaped = [regex]::escape("INSERT [dbo].[dbatoolsci_temp] ([name], [database_id],")
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Table dbatoolsci_example | Export-DbaDbTableData -Passthru
            "$results" | Should -Match $escaped
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Table dbatoolsci_temp | Export-DbaDbTableData -Passthru
            "$results" | Should -Match $secondescaped
        }

        It "supports piping more than one table" {
            $escaped = [regex]::escape("INSERT [dbo].[dbatoolsci_example] ([id]) VALUES (1)")
            $secondescaped = [regex]::escape("INSERT [dbo].[dbatoolsci_temp] ([name], [database_id],")
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Table dbatoolsci_example, dbatoolsci_temp | Export-DbaDbTableData -Passthru
            "$results" | Should -Match $escaped
            "$results" | Should -Match $secondescaped
        }

        It "writes every piped table into the same file without -Append" {
            # Each table used to overwrite the file written for the table before it (#9044)
            $filePath = "$exportPath\pipedtables.sql"
            $null = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Table dbatoolsci_example, dbatoolsci_temp | Export-DbaDbTableData -FilePath $filePath
            $content = Get-Content -Path $filePath -Raw
            $content | Should -Match ([regex]::Escape("INSERT [dbo].[dbatoolsci_example] ([id]) VALUES (1)"))
            $content | Should -Match ([regex]::Escape("INSERT [dbo].[dbatoolsci_temp] ([name], [database_id],"))
            $content | Should -Match ([regex]::Escape("USE [tempdb]"))
            $content | Should -Match "(?m)^GO\r?$"
            $WarnVar | Should -BeNullOrEmpty
        }

        It "omits the USE statement when the scripting options exclude the database context" {
            $options = New-DbaScriptingOption
            $options.ScriptSchema = $false
            $options.ScriptData = $true
            $options.IncludeDatabaseContext = $false
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Table dbatoolsci_example | Export-DbaDbTableData -ScriptingOptionsObject $options -Passthru
            "$results" | Should -Match ([regex]::Escape("INSERT [dbo].[dbatoolsci_example] ([id]) VALUES (1)"))
            "$results" | Should -Not -Match ([regex]::Escape("USE ["))
            $WarnVar | Should -BeNullOrEmpty
        }
    }
}