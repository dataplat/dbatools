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
        # sp_configure exists on every SQL 2005+ instance, so no server-side fixture is needed -
        # only a scratch directory for the exported scripts. No dbatools command runs here, so no
        # EnableException default toggle either (nothing would consume it, and an aborted setup
        # must not leak a mutated shared default).
        $random = Get-Random
        $exportDir = Join-Path -Path $TestConfig.Temp -ChildPath "dbatoolsci_spcfg_$random"
        $splatNewDir = @{
            ItemType = "Directory"
            Force    = $true
            Path     = $exportDir
        }
        $null = New-Item @splatNewDir
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
            # Arrange advanced options ON so the command does not toggle mid-run: the values it
            # writes then match a steady fresh read, and no trailing reset line exists to mask a
            # missing property line. Restore the original setting in finally.
            $configServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $original = $configServer.Configuration.ShowAdvancedOptions.ConfigValue
            try {
                $configServer.Configuration.ShowAdvancedOptions.ConfigValue = 1
                $configServer.Configuration.Alter($true)

                $filePath = Join-Path -Path $exportDir -ChildPath "spcfg_filepath_$random.sql"
                $result = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -FilePath $filePath
                $result | Should -BeOfType System.IO.FileInfo
                @($result).Count | Should -Be 1
                $result.FullName | Should -Be $filePath
                Test-Path -Path $filePath | Should -BeTrue

                $content = Get-Content -Path $filePath -Raw
                # complete header, anchored at start-of-file and quote-exact ([char]39 builds the
                # single quotes the style guide forbids as literals; the source emits two spaces
                # before RECONFIGURE).
                $expectedHeader = "EXEC sp_configure " + [char]39 + "show advanced options" + [char]39 + " , 1;  RECONFIGURE WITH OVERRIDE"
                $content | Should -Match ("^" + [regex]::Escape($expectedHeader))
                # every configuration property is scripted as a quote-exact line carrying its
                # display name. The VALUE is not pinned: other suites legitimately mutate config
                # values on the shared instance (max server memory et al.) between the write and
                # this read-back, so pinning values races them - name-per-line completeness is the
                # stable contract.
                $lines = Get-Content -Path $filePath
                $verifyServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
                foreach ($prop in $verifyServer.Configuration.Properties) {
                    $expectedPrefix = "EXEC sp_configure " + [char]39 + $prop.DisplayName + [char]39 + " , "
                    ($lines | Where-Object { $PSItem.StartsWith($expectedPrefix) -and $PSItem.EndsWith(";") }).Count | Should -BeGreaterThan 0
                }
            } finally {
                # conditional restore: only put the original back if the value is still the one
                # THIS test set - a blind write-back would clobber a concurrent suite's change.
                $restoreServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
                if ([int]$restoreServer.Configuration.ShowAdvancedOptions.ConfigValue -eq 1) {
                    $restoreServer.Configuration.ShowAdvancedOptions.ConfigValue = [int]$original
                    $restoreServer.Configuration.Alter($true)
                }
            }
        }

        It "Auto-generates a .sql file name under -Path" {
            $result = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -Path $exportDir
            $result | Should -BeOfType System.IO.FileInfo
            @($result).Count | Should -Be 1
            $result.Extension | Should -Be ".sql"
            $result.DirectoryName | Should -Be $exportDir
            # Get-ExportFilePath builds "<server>-<timestamp>-<caller>.sql"; the caller token for
            # this command resolves to "spconfigure" (Export-Dba stripped and lowercased).
            $serverToken = [regex]::Escape($TestConfig.InstanceSingle.ToString().Replace([char]92, [char]36))
            $result.Name | Should -Match "^$serverToken-.+-spconfigure\.sql$"
            (Get-Content -Path $result.FullName -Raw) | Should -Match "EXEC sp_configure"
        }

        It "Restores show advanced options to 0 and emits the reset statements when it started disabled" {
            # Arrange advanced options OFF so the toggle-and-restore branch actually runs (asserting
            # before==after is vacuous if the setting already started enabled). Restore the original
            # value in finally so the shared instance is never left mutated.
            $configServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $original = $configServer.Configuration.ShowAdvancedOptions.ConfigValue
            try {
                $configServer.Configuration.ShowAdvancedOptions.ConfigValue = 0
                $configServer.Configuration.Alter($true)

                $togglePath = Join-Path -Path $exportDir -ChildPath "spcfg_toggle_$random.sql"
                $null = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -FilePath $togglePath

                # the command put the setting back to 0 after reading every property
                $after = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).Configuration.ShowAdvancedOptions.ConfigValue
                [int]$after | Should -Be 0

                # the trailing reset statements are emitted only when advanced options started at 0;
                # assert the quote-exact reset statement AND its following RECONFIGURE together at
                # end-of-file so the header's own RECONFIGURE (line 1) cannot satisfy this on its own.
                $content = Get-Content -Path $togglePath -Raw
                $expectedReset = "EXEC sp_configure " + [char]39 + "show advanced options" + [char]39 + " , 0;"
                $content | Should -Match ([regex]::Escape($expectedReset) + "\s*RECONFIGURE WITH OVERRIDE\s*$")
            } finally {
                # conditional restore, same rationale as above: the command itself already reset
                # the value to 0; only restore if nothing else has moved it since.
                $restoreServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
                if ([int]$restoreServer.Configuration.ShowAdvancedOptions.ConfigValue -eq 0) {
                    $restoreServer.Configuration.ShowAdvancedOptions.ConfigValue = [int]$original
                    $restoreServer.Configuration.Alter($true)
                }
            }
        }

        # NOTE: one-file-per-instance across MULTIPLE distinct instances is intentionally not
        # asserted. Get-ExportFilePath auto-names as "<server>-<timestamp>-spconfigure.sql", so
        # passing the same instance twice would collide on an identical same-second path and could
        # not distinguish one-file-per-instance from an overwrite. Proving it needs two distinct
        # live instances, which this feeder's single-instance (InstanceSingle) lab does not provide
        # - DEFERRED-TO-GATE for an integrator with a multi-instance lab.
    }
}