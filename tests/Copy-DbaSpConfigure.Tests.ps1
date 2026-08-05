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
            $singlePlantedValue = $suiteSourceQueryTimeout + 37
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
            $restartPlantedValue = $restartSourceValue + 55
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
            $absentConfigName = "AllowFilesystemEnumeration"
            $absentDestConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1

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

            $absentDestRowCount = $absentDestConn.Query("SELECT COUNT(*) AS ConfigCount FROM sys.configurations WHERE name = N'allow filesystem enumeration'").ConfigCount

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

            $failurePlantedValue = $suiteSourceQueryTimeout + 41
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
            $whatIfPlantedValue = $suiteSourceQueryTimeout + 23
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
            $filterPlantedQueryTimeout = $suiteSourceQueryTimeout + 19
            $filterPlantedLoginTimeout = $filterSourceLoginTimeout + 7
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

            $excludeOnlyPlantedValue = $suiteSourceQueryTimeout + 13
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
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have had something to exclude" {
            # Without this the leg below passes on a run where the exclusion list came out empty,
            # which would prove nothing about the exclude half of the filter.
            @($excludeOnlyProtected).Count | Should -BeGreaterThan 0
        }

        It "Should copy only the setting that was not excluded" {
            $excludeOnlyResults.Count | Should -Be 1
            $excludeOnlyResults[0].Name | Should -Be "RemoteQueryTimeout"
            $excludeOnlyResults[0].Status | Should -Be "Successful"
            $excludeOnlyAfterLookup["RemoteQueryTimeout"] | Should -Be $suiteSourceQueryTimeout
        }

        It "Should leave every excluded setting where it was" {
            $excludeOnlyMoved -join ", " | Should -Be ""
        }
    }

}
