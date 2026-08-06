#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "ConfigName",
                "ExcludeConfigName",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Every leg reads the destination back out of sys.configurations rather than trusting the
        # status object the command hands back: the point of these tests is telling a copy that
        # happened apart from a copy that only reported itself.
        $readConfigValueSql = "SELECT CAST(value AS bigint) AS ConfigValue FROM sys.configurations WHERE name = N'{0}'"

        $suiteSourceConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $suiteDestConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

        $suiteSourceQueryTimeout = $suiteSourceConn.Query(($readConfigValueSql -f "remote query timeout (s)")).ConfigValue
        $suiteDestQueryTimeout = $suiteDestConn.Query(($readConfigValueSql -f "remote query timeout (s)")).ConfigValue
        $suiteDestLoginTimeout = $suiteDestConn.Query(($readConfigValueSql -f "remote login timeout (s)")).ConfigValue
        $suiteDestFillFactor = $suiteDestConn.Query(($readConfigValueSql -f "fill factor (%)")).ConfigValue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Belt and braces over each Context's own restore: sp_configure is instance-wide state on a
        # lab box other windows gate against, so nothing this suite touches is left moved.
        #
        # Every Set-DbaSpConfigure in this file opts out of EnableException, because that command
        # raises when the value you ask for is already the value there - and both the plants and
        # the restores here are asking for a STATE, not for a write. Nothing is swallowed by it:
        # each planted value is read back out of sys.configurations and asserted before the leg
        # that depends on it, so a plant that failed for a real reason reds its own leg.
        $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $suiteDestQueryTimeout -WarningAction SilentlyContinue -EnableException:$false
        $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteLoginTimeout -Value $suiteDestLoginTimeout -WarningAction SilentlyContinue -EnableException:$false
        $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name FillFactor -Value $suiteDestFillFactor -WarningAction SilentlyContinue -EnableException:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When a configuration value differs from the source" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $singleDestConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            # Every planted value in this file is picked from inside the setting's
            # sys.configurations range and then checked against the source's, rather than offset
            # from the source's. An offset is only in range for as long as the instance it is
            # measured from stays low, and a fixture that a lab's own configuration can push out
            # of range fails in setup, where the failure looks like the command's.
            $singlePlantedValue = if ($suiteSourceQueryTimeout -eq 4137) { 4138 } else { 4137 }
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $singlePlantedValue -WarningAction SilentlyContinue -EnableException:$false
            $singleDestValueBefore = $singleDestConn.Query(($readConfigValueSql -f "remote query timeout (s)")).ConfigValue

            $splatSingleCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ConfigName  = "RemoteQueryTimeout"
            }
            $singleCopyResults = @(Copy-DbaSpConfigure @splatSingleCopy)

            $singleDestValueAfter = $singleDestConn.Query(($readConfigValueSql -f "remote query timeout (s)")).ConfigValue

            $singleSourceConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $singleSourceValueAfter = $singleSourceConn.Query(($readConfigValueSql -f "remote query timeout (s)")).ConfigValue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $suiteDestQueryTimeout -WarningAction SilentlyContinue -EnableException:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should emit exactly one status object naming the configuration" {
            $singleCopyResults.Count | Should -Be 1
            $singleCopyResults[0].Name | Should -Be "RemoteQueryTimeout"
            $singleCopyResults[0].Type | Should -Be "Configuration Value"
            $singleCopyResults[0].Status | Should -Be "Successful"
        }

        It "Should name both ends of the copy on the status object" {
            $singleCopyResults[0].SourceServer | Should -Not -BeNullOrEmpty
            $singleCopyResults[0].DestinationServer | Should -Not -BeNullOrEmpty
            $singleCopyResults[0].SourceServer | Should -Not -Be $singleCopyResults[0].DestinationServer
        }

        It "Should have started from a destination value that differed" {
            $singleDestValueBefore | Should -Be $singlePlantedValue
            $singleDestValueBefore | Should -Not -Be $suiteSourceQueryTimeout
        }

        It "Should leave the destination holding the source value" {
            $singleDestValueAfter | Should -Not -Be $singlePlantedValue
            $singleDestValueAfter | Should -Be $suiteSourceQueryTimeout
        }

        It "Should not touch the source" {
            $singleSourceValueAfter | Should -Be $suiteSourceQueryTimeout
        }

        It "Should leave Notes empty for a dynamic setting" {
            # remote query timeout is is_dynamic, so the restart note is the branch NOT taken.
            $singleCopyResults[0].Notes | Should -BeNullOrEmpty
        }
    }

    Context "When the destination already holds the source value" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $matchDestConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $suiteSourceQueryTimeout -WarningAction SilentlyContinue -EnableException:$false

            $splatMatchCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ConfigName  = "RemoteQueryTimeout"
            }
            $matchCopyResults = Copy-DbaSpConfigure @splatMatchCopy

            $matchDestValueAfter = $matchDestConn.Query(($readConfigValueSql -f "remote query timeout (s)")).ConfigValue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $suiteDestQueryTimeout -WarningAction SilentlyContinue -EnableException:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should emit nothing when there is nothing to change" {
            # A matching value never reaches a ShouldProcess block, so no status object exists for
            # it - the command reports work done, not settings inspected.
            @($matchCopyResults).Count | Should -Be 0
        }

        It "Should leave the destination value where it was" {
            $matchDestValueAfter | Should -Be $suiteSourceQueryTimeout
        }
    }

    Context "When the copied setting needs a restart to take effect" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $restartDestConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $restartSourceConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $restartSourceValue = $restartSourceConn.Query(($readConfigValueSql -f "fill factor (%)")).ConfigValue

            # fill factor is the non-dynamic setting in this pair: the configured value moves, the
            # running value does not until a restart, which is the state the note reports.
            #
            # It is also the one bounded setting this file plants - sys.configurations gives it
            # min 0, max 100, where the two timeouts run to 2147483647. So the planted value is
            # picked from inside that range rather than offset from the source's, which would be
            # refused as out of range on an instance already carrying a high fill factor.
            if ($restartSourceValue -eq 50) {
                $restartPlantedValue = 60
            } else {
                $restartPlantedValue = 50
            }
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name FillFactor -Value $restartPlantedValue -WarningAction SilentlyContinue -EnableException:$false
            $restartDestValueBefore = $restartDestConn.Query(($readConfigValueSql -f "fill factor (%)")).ConfigValue

            $splatRestartCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ConfigName  = "FillFactor"
            }
            $restartCopyResults = @(Copy-DbaSpConfigure @splatRestartCopy)

            $restartDestValueAfter = $restartDestConn.Query(($readConfigValueSql -f "fill factor (%)")).ConfigValue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name FillFactor -Value $suiteDestFillFactor -WarningAction SilentlyContinue -EnableException:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should report the restart requirement in Notes" {
            $restartCopyResults.Count | Should -Be 1
            $restartCopyResults[0].Status | Should -Be "Successful"
            $restartCopyResults[0].Notes | Should -Be "Requires restart"
        }

        It "Should still move the configured value" {
            $restartDestValueBefore | Should -Be $restartPlantedValue
            $restartDestValueAfter | Should -Be $restartSourceValue
        }
    }

    Context "When the configuration does not exist on the destination" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Copied the other way round on purpose: the newer instance carries settings the older
            # one has never heard of, which is the only way to reach this branch without inventing
            # a fixture. Nothing is written, so there is nothing to restore.
            #
            # Which settings those are is discovered rather than named. It moves with the version
            # pair, and a literal name quietly stops reaching the branch the day the two copy
            # instances are the same version or swap order - the call still succeeds, it just
            # copies a setting that exists on both and the leg proves something else.
            $absentDestConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1

            $absentSourceProps = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2
            $absentDestNames = @((Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy1).ConfigName)
            $absentCandidate = $absentSourceProps | Where-Object { $PSItem.ConfigName -notin $absentDestNames } | Select-Object -First 1
            $absentConfigName = $absentCandidate.ConfigName
            $absentDisplayName = $absentCandidate.DisplayName

            # Guarded, not skipped. -ConfigName $null does not filter to nothing in the command's
            # single filter expression - it falls through and copies EVERY setting, which on a
            # shared lab instance is the last thing an unattended run should do.
            $absentCopyResults = @()
            $absentTwoDestinationResults = @()
            $absentDestRowCount = -1

            if ($absentConfigName) {
                $splatAbsentCopy = @{
                    Source      = $TestConfig.InstanceCopy2
                    Destination = $TestConfig.InstanceCopy1
                    ConfigName  = $absentConfigName
                }
                $absentCopyResults = @(Copy-DbaSpConfigure @splatAbsentCopy)

                # The same call with the destination named twice: the source loop is walked once per
                # destination, so a two-element -Destination has to yield two status objects. This is
                # the one branch that can prove it without writing anything anywhere.
                $splatAbsentTwoDestinations = @{
                    Source      = $TestConfig.InstanceCopy2
                    Destination = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy1
                    ConfigName  = $absentConfigName
                }
                $absentTwoDestinationResults = @(Copy-DbaSpConfigure @splatAbsentTwoDestinations)

                $absentDestRowCount = $absentDestConn.Query("SELECT COUNT(*) AS ConfigCount FROM sys.configurations WHERE name = N'$absentDisplayName'").ConfigCount
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should report the setting as skipped" {
            $absentCopyResults.Count | Should -Be 1
            $absentCopyResults[0].Name | Should -Be $absentConfigName
            $absentCopyResults[0].Status | Should -Be "Skipped"
            $absentCopyResults[0].Notes | Should -Be "Configuration does not exist on destination"
        }

        It "Should walk the source once per destination" {
            $absentTwoDestinationResults.Count | Should -Be 2
            @($absentTwoDestinationResults | Where-Object Status -eq "Skipped").Count | Should -Be 2
        }

        It "Should not invent the setting on the destination" {
            $absentDestRowCount | Should -Be 0
        }
    }

    Context "When the destination refuses the change" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $failureLoginName = "dbatoolsci_spconfig_$(Get-Random)"
            # Generated per run rather than written into the file: this is a real SQL principal on
            # a lab instance, and a cleanup that did not complete would otherwise leave an account
            # anyone reading this suite could sign in with. Nothing here authenticates as it beyond
            # the refused write, so the value only has to be unguessable.
            $failurePassword = "$([guid]::NewGuid().ToString())Aa1!"

            $failureAdminConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $failureAdminConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$failureLoginName') DROP LOGIN [$failureLoginName]")
            $failureAdminConn.Query("CREATE LOGIN [$failureLoginName] WITH PASSWORD = N'$failurePassword', CHECK_POLICY = OFF")

            $failureSecurePassword = ConvertTo-SecureString $failurePassword -AsPlainText -Force
            $failureCredential = New-Object System.Management.Automation.PSCredential($failureLoginName, $failureSecurePassword)

            $failurePlantedValue = if ($suiteSourceQueryTimeout -eq 4141) { 4142 } else { 4141 }
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $failurePlantedValue -WarningAction SilentlyContinue -EnableException:$false

            # A login holding nothing but public can read sys.configurations and cannot change it,
            # so the read that decides there is work to do succeeds and only the write is refused.
            $splatFailureCopy = @{
                Source                   = $TestConfig.InstanceCopy1
                Destination              = $TestConfig.InstanceCopy2
                DestinationSqlCredential = $failureCredential
                ConfigName               = "RemoteQueryTimeout"
            }
            $failureCopyResults = @(Copy-DbaSpConfigure @splatFailureCopy)

            $failureDestValueAfter = $failureAdminConn.Query(($readConfigValueSql -f "remote query timeout (s)")).ConfigValue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $failureCleanupConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            # The refused copy leaves the login connected through the connection pool, and a
            # connected principal cannot be dropped - so its sessions go first.
            $failureCleanupSql = @"
DECLARE @killStatements nvarchar(max) = N'';
SELECT @killStatements += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';'
FROM sys.dm_exec_sessions WHERE login_name = N'$failureLoginName';
IF @killStatements <> N'' EXEC sp_executesql @killStatements;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$failureLoginName') DROP LOGIN [$failureLoginName];
"@
            $failureCleanupConn.Query($failureCleanupSql) | Out-Null

            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $suiteDestQueryTimeout -WarningAction SilentlyContinue -EnableException:$false

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should report the setting as failed" {
            $failureCopyResults.Count | Should -Be 1
            $failureCopyResults[0].Name | Should -Be "RemoteQueryTimeout"
            $failureCopyResults[0].Status | Should -Be "Failed"
        }

        It "Should carry the reason the destination gave" {
            # Notes comes from the private Get-ErrorMessage, so an empty note here is the tell that
            # the command lost the module scope those private helpers resolve in.
            $failureCopyResults[0].Notes | Should -Not -BeNullOrEmpty
            $failureCopyResults[0].Notes | Should -BeLike "*permission*"
        }

        It "Should leave the destination value untouched" {
            $failureDestValueAfter | Should -Be $failurePlantedValue
        }
    }

    Context "When run with -WhatIf" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $whatIfDestConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $whatIfPlantedValue = if ($suiteSourceQueryTimeout -eq 4123) { 4124 } else { 4123 }
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $whatIfPlantedValue -WarningAction SilentlyContinue -EnableException:$false

            $splatWhatIfCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ConfigName  = "RemoteQueryTimeout"
                WhatIf      = $true
            }
            $whatIfCopyResults = Copy-DbaSpConfigure @splatWhatIfCopy

            $whatIfDestValueAfter = $whatIfDestConn.Query(($readConfigValueSql -f "remote query timeout (s)")).ConfigValue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $suiteDestQueryTimeout -WarningAction SilentlyContinue -EnableException:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should not change the destination" {
            $whatIfDestValueAfter | Should -Be $whatIfPlantedValue
            $whatIfDestValueAfter | Should -Not -Be $suiteSourceQueryTimeout
        }

        It "Should not emit a result object" {
            # Every emit sits inside a ShouldProcess block, so -WhatIf suppresses the status object
            # along with the work it describes.
            @($whatIfCopyResults).Count | Should -Be 0
        }
    }

    Context "When filtering which configurations are copied" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $filterSourceConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $filterSourceLoginTimeout = $filterSourceConn.Query(($readConfigValueSql -f "remote login timeout (s)")).ConfigValue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        BeforeEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $filterDestConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $filterPlantedQueryTimeout = if ($suiteSourceQueryTimeout -eq 4119) { 4120 } else { 4119 }
            $filterPlantedLoginTimeout = if ($filterSourceLoginTimeout -eq 317) { 318 } else { 317 }
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $filterPlantedQueryTimeout -WarningAction SilentlyContinue -EnableException:$false
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteLoginTimeout -Value $filterPlantedLoginTimeout -WarningAction SilentlyContinue -EnableException:$false

            $filterDestBeforeQueryTimeout = $filterDestConn.Query(($readConfigValueSql -f "remote query timeout (s)")).ConfigValue
            $filterDestBeforeLoginTimeout = $filterDestConn.Query(($readConfigValueSql -f "remote login timeout (s)")).ConfigValue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $suiteDestQueryTimeout -WarningAction SilentlyContinue -EnableException:$false
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteLoginTimeout -Value $suiteDestLoginTimeout -WarningAction SilentlyContinue -EnableException:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should copy every configuration named in a single call" {
            $filterDestBeforeQueryTimeout | Should -Be $filterPlantedQueryTimeout
            $filterDestBeforeLoginTimeout | Should -Be $filterPlantedLoginTimeout

            $splatCopyBoth = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ConfigName  = "RemoteQueryTimeout", "RemoteLoginTimeout"
            }
            $filterBothResults = @(Copy-DbaSpConfigure @splatCopyBoth)

            $filterBothResults.Count | Should -Be 2
            $filterBothResults.Name | Should -Contain "RemoteQueryTimeout"
            $filterBothResults.Name | Should -Contain "RemoteLoginTimeout"
            @($filterBothResults | Where-Object Status -eq "Successful").Count | Should -Be 2

            $filterBothQueryTimeout = $filterDestConn.Query(($readConfigValueSql -f "remote query timeout (s)")).ConfigValue
            $filterBothLoginTimeout = $filterDestConn.Query(($readConfigValueSql -f "remote login timeout (s)")).ConfigValue
            $filterBothQueryTimeout | Should -Be $suiteSourceQueryTimeout
            $filterBothLoginTimeout | Should -Be $filterSourceLoginTimeout
        }

        It "Should skip the configuration named in -ExcludeConfigName" {
            $filterDestBeforeQueryTimeout | Should -Be $filterPlantedQueryTimeout
            $filterDestBeforeLoginTimeout | Should -Be $filterPlantedLoginTimeout

            $splatCopyExcluded = @{
                Source            = $TestConfig.InstanceCopy1
                Destination       = $TestConfig.InstanceCopy2
                ConfigName        = "RemoteQueryTimeout", "RemoteLoginTimeout"
                ExcludeConfigName = "RemoteLoginTimeout"
            }
            $filterExcludedResults = @(Copy-DbaSpConfigure @splatCopyExcluded)

            $filterExcludedResults.Count | Should -Be 1
            $filterExcludedResults[0].Name | Should -Be "RemoteQueryTimeout"

            $filterExcludedLoginTimeout = $filterDestConn.Query(($readConfigValueSql -f "remote login timeout (s)")).ConfigValue
            $filterExcludedLoginTimeout | Should -Be $filterPlantedLoginTimeout
        }
    }

    Context "When -ExcludeConfigName is used without -ConfigName" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # -and binds tighter than -or in the source's single filter expression, so the exclude
            # half stands on its own and this call really does walk every setting on the source.
            # Everything that already differs is therefore excluded by measurement rather than from
            # a hard-coded list, which keeps an unattended run from rewriting a shared lab instance
            # if the two instances drift further apart than they are today.
            #
            # Measurement alone would leave the leg standing on that drift existing: two instances
            # configured identically produce an empty exclusion list and the exclude half is then
            # never exercised at all. So one setting is deliberately planted apart first, before the
            # measurement reads either side, which puts a known name in the list on any pair.
            $excludeOnlySourceLoginTimeout = $suiteSourceConn.Query(($readConfigValueSql -f "remote login timeout (s)")).ConfigValue
            $excludeOnlyPlantedLoginTimeout = if ($excludeOnlySourceLoginTimeout -eq 309) { 310 } else { 309 }
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteLoginTimeout -Value $excludeOnlyPlantedLoginTimeout -WarningAction SilentlyContinue -EnableException:$false
            $excludeOnlyDestBeforeLoginTimeout = $suiteDestConn.Query(($readConfigValueSql -f "remote login timeout (s)")).ConfigValue

            $excludeOnlySourceProps = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy1
            $excludeOnlyDestProps = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2

            $excludeOnlyDestLookup = New-Object -TypeName System.Collections.Hashtable
            foreach ($excludeOnlyDestProp in $excludeOnlyDestProps) {
                $excludeOnlyDestLookup[$excludeOnlyDestProp.ConfigName] = $excludeOnlyDestProp.ConfiguredValue
            }

            $excludeOnlyProtected = @()
            foreach ($excludeOnlySourceProp in $excludeOnlySourceProps) {
                if (-not $excludeOnlyDestLookup.ContainsKey($excludeOnlySourceProp.ConfigName)) {
                    continue
                }
                if ($excludeOnlySourceProp.ConfiguredValue -ne $excludeOnlyDestLookup[$excludeOnlySourceProp.ConfigName]) {
                    $excludeOnlyProtected += $excludeOnlySourceProp.ConfigName
                }
            }
            $excludeOnlyProtected = @($excludeOnlyProtected | Where-Object { $PSItem -ne "RemoteQueryTimeout" } | Select-Object -Unique)

            $excludeOnlyProtectedBefore = New-Object -TypeName System.Collections.Hashtable
            foreach ($excludeOnlyProtectedName in $excludeOnlyProtected) {
                $excludeOnlyProtectedBefore[$excludeOnlyProtectedName] = $excludeOnlyDestLookup[$excludeOnlyProtectedName]
            }

            $excludeOnlyPlantedValue = if ($suiteSourceQueryTimeout -eq 4113) { 4114 } else { 4113 }
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $excludeOnlyPlantedValue -WarningAction SilentlyContinue -EnableException:$false

            $splatExcludeOnlyCopy = @{
                Source            = $TestConfig.InstanceCopy1
                Destination       = $TestConfig.InstanceCopy2
                ExcludeConfigName = $excludeOnlyProtected
            }
            $excludeOnlyResults = @(Copy-DbaSpConfigure @splatExcludeOnlyCopy)

            $excludeOnlyAfterProps = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2
            $excludeOnlyAfterLookup = New-Object -TypeName System.Collections.Hashtable
            foreach ($excludeOnlyAfterProp in $excludeOnlyAfterProps) {
                $excludeOnlyAfterLookup[$excludeOnlyAfterProp.ConfigName] = $excludeOnlyAfterProp.ConfiguredValue
            }

            $excludeOnlyMoved = @()
            foreach ($excludeOnlyCheckName in $excludeOnlyProtected) {
                if ($excludeOnlyAfterLookup[$excludeOnlyCheckName] -ne $excludeOnlyProtectedBefore[$excludeOnlyCheckName]) {
                    $excludeOnlyMoved += $excludeOnlyCheckName
                }
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteQueryTimeout -Value $suiteDestQueryTimeout -WarningAction SilentlyContinue -EnableException:$false
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name RemoteLoginTimeout -Value $suiteDestLoginTimeout -WarningAction SilentlyContinue -EnableException:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have had something to exclude" {
            # Without this the leg below passes on a run where the exclusion list came out empty,
            # which would prove nothing about the exclude half of the filter. Naming the planted
            # setting rather than counting the list is what makes that deterministic - a count is
            # satisfied by whatever drift the lab happens to be carrying that day.
            $excludeOnlyDestBeforeLoginTimeout | Should -Be $excludeOnlyPlantedLoginTimeout
            $excludeOnlyDestBeforeLoginTimeout | Should -Not -Be $excludeOnlySourceLoginTimeout
            $excludeOnlyProtected | Should -Contain "RemoteLoginTimeout"
        }

        It "Should copy only the setting that was not excluded" {
            $excludeOnlyResults.Count | Should -Be 1
            $excludeOnlyResults[0].Name | Should -Be "RemoteQueryTimeout"
            $excludeOnlyResults[0].Status | Should -Be "Successful"
            $excludeOnlyAfterLookup["RemoteQueryTimeout"] | Should -Be $suiteSourceQueryTimeout
        }

        It "Should leave every excluded setting where it was" {
            $excludeOnlyMoved -join ", " | Should -Be ""
            $excludeOnlyAfterLookup["RemoteLoginTimeout"] | Should -Be $excludeOnlyPlantedLoginTimeout
        }
    }

    Context "When resolving the command name in a cold shell" {
        BeforeAll {
            # Every other leg runs in a session that imported dbatools long before Pester started,
            # so none of them can tell the binary cmdlet apart from the retired script function -
            # whichever got there first answers to the name. This leg starts a shell of the same
            # edition that has imported nothing, loads the module the way a consumer does, and asks
            # what the name resolves to. dbatools.psm1 is the import under test on purpose: it is
            # the loader that pulls the satellite in by path, and importing the manifest by name
            # cannot work in a dev tree because the satellites are not on PSModulePath.
            $moduleBase = @(Get-Module -Name dbatools)[0].ModuleBase
            $shellPath = (Get-Process -Id $PID).Path

            # This file is EXECUTED, so where it lives matters as much as what is in it. It goes in
            # a per-invocation directory that only its creator and the machine's administrators can
            # write to, rather than in the shared temp root, under a GUID name, and created below
            # with CreateNew rather than written over whatever is at the path. Closing the write
            # handle before the run is only safe because of the directory: on the shared temp root
            # there is a window between the write and the run in which anyone can substitute the
            # script.
            $probeDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-resolve-$([guid]::NewGuid().ToString("N"))"

            # A GUID makes this unreachable in practice, but every create-directory API below
            # succeeds silently on a path that already exists and leaves its permissions alone, so
            # the one thing that must not happen is adopting somebody else's directory and
            # executing a script out of it.
            if (Test-Path -LiteralPath $probeDirectory) {
                throw "$probeDirectory already exists - this run will not execute a script out of a directory it did not create"
            }

            # Only a directory this block actually created may be deleted in AfterAll. Without the
            # flag the throw above hands the cleanup a path it just refused to touch, and refusing
            # to execute out of somebody else's directory while recursively deleting it is worse
            # than either outcome on its own.
            $probeDirectoryCreated = $false
            $probeDirectoryInfo = New-Object System.IO.DirectoryInfo($probeDirectory)

            if ([System.Environment]::OSVersion.Platform -eq "Win32NT") {
                # The running identity owns it, not Administrators: only an elevated run can hand
                # ownership to a group it is not in, and a descriptor that omits the creator locks
                # the creator out of the directory it just made. Administrators and SYSTEM are on it
                # because they can reach the file whatever this says, so excluding them buys nothing
                # and costs the elevated case.
                $currentSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User
                $administratorsSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
                $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)

                $probeSecurity = New-Object System.Security.AccessControl.DirectorySecurity
                $probeSecurity.SetAccessRuleProtection($true, $false)
                $probeSecurity.SetOwner($currentSid)
                foreach ($trusteeSid in $currentSid, $administratorsSid, $systemSid) {
                    $probeRule = New-Object System.Security.AccessControl.FileSystemAccessRule($trusteeSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
                    $probeSecurity.AddAccessRule($probeRule)
                }

                # Created WITH the descriptor, never created and then secured - the gap between
                # those two calls carries inherited permissions. Which call does it differs by
                # edition: .NET Framework has DirectoryInfo.Create(DirectorySecurity), .NET moved it
                # out to FileSystemAclExtensions, and Directory.CreateDirectory(path, security)
                # exists on neither PowerShell 7 nor v3. Probing for the overload rather than the
                # PSEdition because it is the overload that decides.
                $probeNativeCreate = [System.IO.DirectoryInfo].GetMethod("Create", [Type[]]@([System.Security.AccessControl.DirectorySecurity]))
                if ($probeNativeCreate) {
                    $probeDirectoryInfo.Create($probeSecurity)
                } else {
                    [System.IO.FileSystemAclExtensions]::Create($probeDirectoryInfo, $probeSecurity)
                }
                $probeDirectoryCreated = $true
            } else {
                # DirectorySecurity is Windows-only and throws PlatformNotSupportedException
                # everywhere else, so the mode carries the same job there. The umask cannot: under a
                # permissive one the directory comes out group- or world-writable and the executed
                # script is substitutable.
                # mkdir rather than a .NET call, for the exclusivity: every managed
                # create-directory API succeeds silently on a directory that already exists and
                # leaves that directory's permissions alone, so a pre-created one would be used as
                # is. mkdir without -p fails instead, and -m carries the mode in the same call.
                # It also sidesteps UnixFileMode, which is .NET 7 and absent on PowerShell 7.2/7.3.
                # A non-zero exit is fatal: carrying on would execute a script out of a directory
                # whose permissions are unknown.
                $null = & /bin/mkdir -m 700 $probeDirectory
                if ($LASTEXITCODE -ne 0) {
                    throw "could not create $probeDirectory with owner-only permissions (mkdir exited $LASTEXITCODE)"
                }
                $probeDirectoryCreated = $true
            }

            $probePath = Join-Path -Path $probeDirectory -ChildPath "resolve.ps1"

            # Get-Command -All so a retired function shadowing the cmdlet shows up as a second
            # entry rather than silently winning; the count is what proves it is not there.
            $probeBody = @"
param(`$ModuleBase)
# The module path is an ARGUMENT, not interpolated text: this script is executed, and a
# path carrying a quote or a $ would otherwise close the string and run as code.
Import-Module -Name (Join-Path -Path `$ModuleBase -ChildPath "dbatools.psm1") -DisableNameChecking
`$resolved = Get-Command -Name Copy-DbaSpConfigure -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaSpConfigure"
    All         = `$true
    ErrorAction = "SilentlyContinue"
}
`$allResolved = @(Get-Command @splatResolveAll)
`$functionCount = @(`$allResolved | Where-Object { `$PSItem.CommandType -eq "Function" }).Count
`$satelliteLoaded = [bool](Get-Module -Name dbatools.migration)
"RESOLVED|`$(`$resolved.CommandType)|`$(`$resolved.ModuleName)|`$functionCount|`$satelliteLoaded"
"@

            $probeStream = New-Object System.IO.FileStream($probePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            try {
                $probeBytes = [System.Text.Encoding]::UTF8.GetBytes($probeBody)
                $probeStream.Write($probeBytes, 0, $probeBytes.Length)
            } finally {
                $probeStream.Dispose()
            }

            $probeArguments = @("-NoProfile", "-NonInteractive", "-File", $probePath, $moduleBase)
            $probeOutput = & $shellPath @probeArguments 2>&1
            $probeFields = @("$(@($probeOutput | Where-Object { "$PSItem" -like "RESOLVED|*" })[0])" -split "\|")
        }

        AfterAll {
            if ($probeDirectoryCreated) {
                $splatRemoveProbeDirectory = @{
                    Path        = $probeDirectory
                    Recurse     = $true
                    Force       = $true
                    ErrorAction = "SilentlyContinue"
                }
                Remove-Item @splatRemoveProbeDirectory
            }
        }

        It "Should resolve to the binary cmdlet shipped by dbatools.migration" {
            $probeFields[1] | Should -Be "Cmdlet"
            $probeFields[2] | Should -Be "dbatools.migration"
        }

        It "Should load the satellite and leave no retired function shadowing the name" {
            $probeFields[4] | Should -Be "True"
            $probeFields[3] | Should -Be "0"
        }
    }
}
