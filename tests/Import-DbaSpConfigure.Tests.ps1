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

            # Export the instance's CURRENT sp_configure so the round-trip test can import a full,
            # realistically-generated file (every setting, not just a hand-built pair). Export-Dba-
            # SpConfigure restores show advanced options itself, so this does not disturb the snapshot.
            $configFile = Join-Path -Path $exportDir -ChildPath "spcfg_export_$random.sql"
            $null = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -FilePath $configFile
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

        It "Round-trips a full Export-DbaSpConfigure file, executing every line" {
            try {
                # Every line of the exported file is a valid batch, so a successful import emits
                # exactly one host "Successfully executed" message per line (Write-Message -Level
                # Output = level 2, inside the default 1-3 information window, so it reaches the
                # information stream). Capture stream 6 and count those messages against the file.
                # The command and this test both read the file with Get-Content, so the line counts
                # line up exactly and prove no line was skipped.
                $lineCount = (Get-Content -Path $configFile).Count
                $splatRoundTrip = @{
                    SqlInstance     = $TestConfig.InstanceSingle
                    Path            = $configFile
                    Confirm         = $false
                    WarningVariable = "warn"
                    WarningAction   = "SilentlyContinue"
                }
                $captured = Import-DbaSpConfigure @splatRoundTrip 6>&1
                # Re-applying the instance's own values fails no line, EXCEPT options the edition
                # refuses to set at all - sp_configure rejects even the current value of an
                # edition-locked option. Tolerate exactly that refusal class and nothing else,
                # and the restart warning still fires.
                $editionRefusals = @($warn | Where-Object { "$PSItem" -match "failed. Feature may not be supported" })
                foreach ($refusal in $editionRefusals) {
                    "$refusal" | Should -Match "not supported in this edition"
                }
                # every warning that is not an edition refusal must be the restart notice - any
                # other warning class fails the round-trip
                $otherWarnings = @($warn | Where-Object { "$PSItem" -notmatch "failed. Feature may not be supported" })
                $otherWarnings.Count | Should -BeGreaterThan 0
                foreach ($otherWarning in $otherWarnings) {
                    "$otherWarning" | Should -Match "updated once SQL Server is restarted"
                }
                # nothing reaches the success pipeline - only host/information records were captured
                ($captured | Where-Object { $PSItem -isnot [System.Management.Automation.InformationRecord] }) | Should -BeNullOrEmpty
                # one success message per executed file line means every line the edition accepts
                # was executed, none skipped
                $successes = $captured | Where-Object { "$PSItem" -match "Successfully executed" }
                $successes.Count | Should -Be ($lineCount - $editionRefusals.Count)
            } finally {
                # the exported file's header enables show advanced options; the command's reset does
                # not Alter it off, so restore it explicitly.
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