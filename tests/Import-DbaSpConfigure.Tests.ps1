#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "SqlInstance",
                "Path",
                "SqlCredential",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $exportDir = Join-Path -Path $TestConfig.Temp -ChildPath "dbatoolsci_impspcfg_$random"
        $splatNewDir = @{
            ItemType = "Directory"
            Force    = $true
            Path     = $exportDir
        }
        $null = New-Item @splatNewDir

        # The execution tests toggle a single benign, dynamic advanced option (cost threshold for
        # parallelism, valid range 0-32767, no restart) to a distinct value and read it back, which
        # proves the file was actually executed. [char]39 builds the single quotes the T-SQL needs
        # without putting forbidden literal single quotes in the test source.
        $q = [char]39
        $cfgName = "cost threshold for parallelism"

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

    Context "Importing from a file" {
        BeforeAll {
            # Snapshot both settings the .sql files touch. The file turns show advanced options ON
            # at the T-SQL level, and the command's FromFile reset only sets the SMO property back
            # without Alter() - so the instance is left with advanced options enabled unless the
            # test restores it. Restore BOTH after each mutating test.
            $srvSnap = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $originalCost = [int]$srvSnap.Configuration.CostThresholdForParallelism.ConfigValue
            $originalAdvanced = [int]$srvSnap.Configuration.ShowAdvancedOptions.ConfigValue
            # a distinct value guaranteed inside the documented 0-32767 range
            $targetCost = if ($originalCost -eq 50) { 60 } else { 50 }
        }

        It "Warns and returns nothing when -Path does not exist" {
            # sysadmin is checked first (passes on the lab), then the missing file is rejected
            # before anything is applied.
            $missingPath = Join-Path -Path $exportDir -ChildPath "does_not_exist_$random.sql"
            $splatMissing = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $missingPath
                Confirm         = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaSpConfigure @splatMissing
            $result | Should -BeNullOrEmpty
            $warn -join " " | Should -Match "File .* Not Found"
        }

        It "Executes the file so the setting actually changes, and returns no pipeline object despite the .OUTPUTS Boolean doc" {
            try {
                $applyFile = Join-Path -Path $exportDir -ChildPath "spcfg_apply_$random.sql"
                $applyLines = @(
                    "EXEC sp_configure ${q}show advanced options${q}, 1; RECONFIGURE WITH OVERRIDE"
                    "EXEC sp_configure ${q}$cfgName${q}, $targetCost; RECONFIGURE WITH OVERRIDE"
                )
                Set-Content -Path $applyFile -Value $applyLines

                $splatImport = @{
                    SqlInstance     = $TestConfig.InstanceSingle
                    Path            = $applyFile
                    Confirm         = $false
                    WarningVariable = "warn"
                    WarningAction   = "SilentlyContinue"
                }
                $result = Import-DbaSpConfigure @splatImport
                # characterization: .OUTPUTS documents System.Boolean, but the command only writes
                # messages and emits NOTHING to the pipeline.
                $result | Should -BeNullOrEmpty
                # the query actually ran - the configured value moved to the target (proves real
                # execution, not just the unconditional restart warning firing on a total failure).
                $after = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).Configuration.CostThresholdForParallelism.ConfigValue
                [int]$after | Should -Be $targetCost
                # the FromFile success path always warns that a restart may be required
                $warn -join " " | Should -Match "updated once SQL Server is restarted"
            } finally {
                $restoreServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
                $restoreServer.Configuration.CostThresholdForParallelism.ConfigValue = $originalCost
                $restoreServer.Configuration.ShowAdvancedOptions.ConfigValue = $originalAdvanced
                $restoreServer.Configuration.Alter($true)
            }
        }

        It "Warns but continues past a failing line and still applies the later valid statement" {
            try {
                # a bogus sp_configure name errors when executed; the command catches it via
                # Stop-Function -Continue and moves on to the next line.
                $badFile = Join-Path -Path $exportDir -ChildPath "spcfg_bad_$random.sql"
                $badOption = "dbatoolsci nonexistent option $random"
                $badLines = @(
                    "EXEC sp_configure ${q}show advanced options${q}, 1; RECONFIGURE WITH OVERRIDE"
                    "EXEC sp_configure ${q}$badOption${q}, 1; RECONFIGURE WITH OVERRIDE"
                    "EXEC sp_configure ${q}$cfgName${q}, $targetCost; RECONFIGURE WITH OVERRIDE"
                )
                Set-Content -Path $badFile -Value $badLines

                $splatBad = @{
                    SqlInstance     = $TestConfig.InstanceSingle
                    Path            = $badFile
                    Confirm         = $false
                    WarningVariable = "warn"
                    WarningAction   = "SilentlyContinue"
                }
                $null = Import-DbaSpConfigure @splatBad
                # the failing line warns...
                $warn -join " " | Should -Match "failed. Feature may not be supported"
                # ...and execution continues, so the later valid line still took effect
                $after = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).Configuration.CostThresholdForParallelism.ConfigValue
                [int]$after | Should -Be $targetCost
            } finally {
                $restoreServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
                $restoreServer.Configuration.CostThresholdForParallelism.ConfigValue = $originalCost
                $restoreServer.Configuration.ShowAdvancedOptions.ConfigValue = $originalAdvanced
                $restoreServer.Configuration.Alter($true)
            }
        }

        It "Does not execute the file or warn about a restart under -WhatIf" {
            try {
                # The entire import block sits inside ShouldProcess, so -WhatIf runs no queries: the
                # value is unchanged and the restart warning (also inside the block) never fires.
                $whatIfFile = Join-Path -Path $exportDir -ChildPath "spcfg_whatif_$random.sql"
                $whatIfLines = @(
                    "EXEC sp_configure ${q}show advanced options${q}, 1; RECONFIGURE WITH OVERRIDE"
                    "EXEC sp_configure ${q}$cfgName${q}, $targetCost; RECONFIGURE WITH OVERRIDE"
                )
                Set-Content -Path $whatIfFile -Value $whatIfLines

                $splatWhatIf = @{
                    SqlInstance     = $TestConfig.InstanceSingle
                    Path            = $whatIfFile
                    WhatIf          = $true
                    WarningVariable = "warn"
                    WarningAction   = "SilentlyContinue"
                }
                $result = Import-DbaSpConfigure @splatWhatIf
                $result | Should -BeNullOrEmpty
                $after = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).Configuration.CostThresholdForParallelism.ConfigValue
                [int]$after | Should -Be $originalCost
                $warn -join " " | Should -Not -Match "updated once SQL Server is restarted"
            } finally {
                # defensive: a regression that ignored -WhatIf would have mutated both settings.
                $restoreServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
                $restoreServer.Configuration.CostThresholdForParallelism.ConfigValue = $originalCost
                $restoreServer.Configuration.ShowAdvancedOptions.ConfigValue = $originalAdvanced
                $restoreServer.Configuration.Alter($true)
            }
        }
    }

    # NOTE: the ServerCopy parameter set (-Source/-Destination) is intentionally not covered here.
    # It migrates configuration between two live instances and its version-mismatch guard compares
    # source vs destination major versions - both require a SECOND distinct instance, which this
    # feeder's single-instance (InstanceSingle) lab does not provide. DEFERRED-TO-GATE for an
    # integrator with a two-instance lab.
}