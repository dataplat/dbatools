#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaSpConfigure",
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
                "Path",
                "FilePath",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
#
#    Integration test should appear below and are custom to the command you are writing.
#    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
#    for more guidence.
#
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # sp_configure exists on every SQL 2005+ instance, so no server-side fixture is needed -
        # only a scratch directory for the exported scripts.
        $random = Get-Random
        $exportDir = Join-Path -Path $TestConfig.Temp -ChildPath "dbatoolsci_spcfg_$random"
        $splatNewDir = @{
            ItemType = "Directory"
            Force    = $true
            Path     = $exportDir
        }
        $null = New-Item @splatNewDir

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $splatCleanupDir = @{
            Path        = $exportDir
            Recurse     = $true
            Force       = $true
            ErrorAction = "SilentlyContinue"
        }
        Remove-Item @splatCleanupDir
    }

    Context "Exporting the configuration" {
        It "Writes the sp_configure script to -FilePath and returns the FileInfo" {
            $filePath = Join-Path -Path $exportDir -ChildPath "spcfg_filepath_$random.sql"
            $result = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -FilePath $filePath
            $result | Should -BeOfType System.IO.FileInfo
            $result.FullName | Should -Be $filePath
            Test-Path -Path $filePath | Should -BeTrue

            $content = Get-Content -Path $filePath -Raw
            # header line enables advanced options (regex dot stands in for the single quotes,
            # which the style guide forbids in source); note the source emits two spaces before
            # RECONFIGURE.
            $content | Should -Match "EXEC sp_configure . show advanced options . , 1;"
            # every configuration property is scripted, so a standard setting is always present
            $content | Should -Match "max degree of parallelism"
            # header plus one line per configuration property means many sp_configure statements
            ([regex]::Matches($content, "EXEC sp_configure")).Count | Should -BeGreaterThan 5
        }

        It "Auto-generates a .sql file name under -Path" {
            $result = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Path $exportDir
            $result | Should -BeOfType System.IO.FileInfo
            $result.Extension | Should -Be ".sql"
            $result.DirectoryName | Should -Be $exportDir
            # Get-ExportFilePath builds "<server>-<timestamp>-<caller>.sql"; the caller token for
            # this command resolves to "spconfigure" (Export-Dba stripped and lowercased).
            $serverToken = [regex]::Escape($TestConfig.InstanceSingle.ToString().Replace([char]92, [char]36))
            $result.Name | Should -Match "^$serverToken-.+-spconfigure\.sql$"
            (Get-Content -Path $result.FullName -Raw) | Should -Match "EXEC sp_configure"
        }

        It "Leaves the show advanced options setting unchanged after the export" {
            # The command toggles advanced options on to read every property, then restores the
            # original value - so the instance-level setting is the same before and after.
            $before = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).Configuration.ShowAdvancedOptions.ConfigValue
            $restorePath = Join-Path -Path $exportDir -ChildPath "spcfg_restore_$random.sql"
            $null = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -FilePath $restorePath
            $after = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).Configuration.ShowAdvancedOptions.ConfigValue
            $after | Should -Be $before
        }

        It "Returns one file per value supplied to -SqlInstance" {
            # Passing the same instance twice exercises the foreach($instance in $SqlInstance) loop
            # without needing a second lab instance: one FileInfo must come back per element.
            $splatMulti = @{
                SqlInstance = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle)
                Path        = $exportDir
            }
            $result = @(Export-DbaSpConfigure @splatMulti)
            $result.Count | Should -Be 2
            $result | ForEach-Object { $PSItem | Should -BeOfType System.IO.FileInfo }
        }
    }
}