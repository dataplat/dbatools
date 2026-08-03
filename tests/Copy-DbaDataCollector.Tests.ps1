#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDataCollector",
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
                "CollectionSet",
                "ExcludeCollectionSet",
                "NoServerReconfig",
                "Force",
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

        # Explain what needs to be set up for the test:
        # The command reads the source CollectorConfigStore and writes to the destination one, and
        # it copies only NON-system collection sets - a stock instance has four and all four are
        # system, so the source needs a user-defined set. It also gives up on any destination whose
        # store reports Enabled false, so the collector has to be turned on at both ends or every
        # leg below would pass while copying nothing. Neither instance ships that way, so the suite
        # builds both and puts the original state back in AfterAll.
        #
        # The command refuses to run when the module-scope $script:isWindows flag is not true. That
        # flag is set while dbatools.psm1 executes, but a Pester run reaches the module with the
        # flag unset, so every leg below would take the refusal branch and assert nothing. Pin it
        # to the real platform value for the duration of the suite and put the original back in
        # AfterAll. The refusal branch itself is covered by its own Context, which flips the same
        # flag the other way.
        $originalIsWindows = InModuleScope -ModuleName dbatools -ScriptBlock { $script:isWindows }
        InModuleScope -ModuleName dbatools -ScriptBlock { $script:isWindows = $true }

        # Set variables. They are available in all the It blocks.
        # A GUID rather than Get-Random: the cleanup drops this name unconditionally, so a collision
        # with a concurrent run would destroy that run's fixture. Get-Random draws from a 32-bit
        # space and repeats often enough on a shared lab to matter.
        $collectionSetName = "dbatoolsci_dc_$([guid]::NewGuid().ToString("N"))"
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $readEnabledSql = "SELECT CAST(parameter_value AS int) AS Enabled FROM msdb.dbo.syscollector_config_store WHERE parameter_name = 'CollectorEnabled'"
        $listUserSetsSql = "SELECT name FROM msdb.dbo.syscollector_collection_sets WHERE is_system = 0"

        # SMO's Query takes no parameters, so the name is quote-doubled instead.
        function Get-DropCollectionSetSql {
            param($SetName)
            $safeSetName = "$SetName".Replace("'", "''")
            return "
IF EXISTS (SELECT 1 FROM msdb.dbo.syscollector_collection_sets WHERE name = N'$safeSetName')
BEGIN
    DECLARE @setId int = (SELECT collection_set_id FROM msdb.dbo.syscollector_collection_sets WHERE name = N'$safeSetName');
    IF (SELECT is_running FROM msdb.dbo.syscollector_collection_sets WHERE collection_set_id = @setId) = 1
        EXEC msdb.dbo.sp_syscollector_stop_collection_set @collection_set_id = @setId;
    EXEC msdb.dbo.sp_syscollector_delete_collection_set @collection_set_id = @setId;
END"
        }
        $dropSetSql = Get-DropCollectionSetSql -SetName $collectionSetName

        # Create the objects.
        $originalSourceCollector = $sourceServer.Query($readEnabledSql).Enabled
        $originalDestCollector = $destServer.Query($readEnabledSql).Enabled
        if ($originalSourceCollector -ne 1) {
            $sourceServer.Query("EXEC msdb.dbo.sp_syscollector_enable_collector")
        }
        if ($originalDestCollector -ne 1) {
            $destServer.Query("EXEC msdb.dbo.sp_syscollector_enable_collector")
        }

        # Several legs call the command with no -CollectionSet, so every non-system set on the
        # source crosses over - which makes the source's set list the blast radius. Establish that it
        # is empty before the fixture set is created and those legs provably cannot carry a
        # stranger's set to the destination. Throws rather than skips, and names what is in the way.
        #
        # No carve-out for the fixture name: the name is a fresh GUID, so anything already standing
        # under it belongs to someone else and is exactly what this guard exists to refuse. The
        # earlier exclusion existed to tolerate a leftover from a previous same-named run, which a
        # unique name makes impossible.
        $preexistingSourceSetNames = @($sourceServer.Query($listUserSetsSql) | Select-Object -ExpandProperty name)
        if (@($preexistingSourceSetNames).Count -gt 0) {
            throw "$($TestConfig.InstanceCopy1) already carries non-system collection sets ($(@($preexistingSourceSetNames) -join ", ")) - the unfiltered legs would copy them, so this suite will not run against it."
        }

        # Recorded so the cleanup can tell what was already on the destination from what appeared
        # during the run.
        $originalDestSetNames = @($destServer.Query($listUserSetsSql) | Select-Object -ExpandProperty name)

        # A non-cached collection set needs one of the stock collector schedules; the item makes the
        # set something ScriptCreate can render into a real create script rather than an empty one.
        # Created outright, with no drop-first: under a unique name there is nothing of ours to
        # clear, and a drop here would only ever hit somebody else's set.
        $sourceServer.Query("
DECLARE @setId int;
EXEC msdb.dbo.sp_syscollector_create_collection_set
    @name = N'$collectionSetName',
    @schedule_name = N'CollectorSchedule_Every_15min',
    @collection_mode = 1,
    @days_until_expiration = 5,
    @description = N'dbatools integration test collection set',
    @collection_set_id = @setId OUTPUT;

DECLARE @typeUid uniqueidentifier = (SELECT collector_type_uid FROM msdb.dbo.syscollector_collector_types WHERE name = N'Generic T-SQL Query Collector Type');
DECLARE @itemId int;
EXEC msdb.dbo.sp_syscollector_create_collection_item
    @name = N'${collectionSetName}_item',
    @parameters = N'<ns:TSQLQueryCollector xmlns:ns=''DataCollectorType''><Query><Value>SELECT 1 AS probe_value</Value><OutputTable>${collectionSetName}_out</OutputTable></Query></ns:TSQLQueryCollector>',
    @collection_item_id = @itemId OUTPUT,
    @frequency = 900,
    @collection_set_id = @setId,
    @collector_type_uid = @typeUid;")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Every restoration below is instance-wide or module-wide state on a shared lab box, so each
        # one runs independently and records its own failure instead of riding on the one before it.
        # Chaining them meant a set that refused to drop left the collector enabled for every other
        # user of the instance, and a destination that refused to disable left the source enabled
        # too. The failures are re-raised at the end so a broken cleanup still fails the run.
        $cleanupFailures = @()

        # The fixture set is dropped by name below. Any OTHER set that appeared on the destination is
        # not demonstrably ours - the BeforeAll precondition established the source carried nothing
        # else to copy, so a set here came from another window - and dropping it on that guess would
        # destroy a peer's fixture. Report it, leave it standing, let the run go red.
        try {
            $unexpectedDestSetNames = @($destServer.Query($listUserSetsSql) | Select-Object -ExpandProperty name) |
                Where-Object { $PSItem -notin $originalDestSetNames -and $PSItem -ne $collectionSetName }
            if (@($unexpectedDestSetNames).Count -gt 0) {
                $cleanupFailures += "collection sets appeared on the destination that this run cannot account for and has left in place: $(@($unexpectedDestSetNames) -join ", ")"
            }
        } catch {
            $cleanupFailures += "destination collection set inventory: $($PSItem.Exception.Message)"
        }

        try {
            $destServer.Query($dropSetSql)
        } catch {
            $cleanupFailures += "destination fixture set: $($PSItem.Exception.Message)"
        }

        try {
            $sourceServer.Query($dropSetSql)
        } catch {
            $cleanupFailures += "source fixture set: $($PSItem.Exception.Message)"
        }

        try {
            if ($originalDestCollector -ne 1) {
                $destServer.Query("IF (SELECT CAST(parameter_value AS int) FROM msdb.dbo.syscollector_config_store WHERE parameter_name = 'CollectorEnabled') = 1 EXEC msdb.dbo.sp_syscollector_disable_collector")
            }
        } catch {
            $cleanupFailures += "destination collector: $($PSItem.Exception.Message)"
        }

        try {
            if ($originalSourceCollector -ne 1) {
                $sourceServer.Query("IF (SELECT CAST(parameter_value AS int) FROM msdb.dbo.syscollector_config_store WHERE parameter_name = 'CollectorEnabled') = 1 EXEC msdb.dbo.sp_syscollector_disable_collector")
            }
        } catch {
            $cleanupFailures += "source collector: $($PSItem.Exception.Message)"
        }

        try {
            $restoreParameters = @{
                OriginalValue = $originalIsWindows
            }
            $splatRestorePlatform = @{
                ModuleName  = "dbatools"
                Parameters  = $restoreParameters
                ScriptBlock = { $script:isWindows = $OriginalValue }
            }
            InModuleScope @splatRestorePlatform
        } catch {
            $cleanupFailures += "platform flag: $($PSItem.Exception.Message)"
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

        if ($cleanupFailures.Count -gt 0) {
            throw "AfterAll could not restore: $($cleanupFailures -join " | ")"
        }
    }

    Context "When previewing the copy with WhatIf" {
        BeforeAll {
            $destServer.Query($dropSetSql)

            $splatWhatIf = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                CollectionSet = $collectionSetName
                WhatIf        = $true
                WarningAction = "SilentlyContinue"
            }
            $whatIfResults = @(Copy-DbaDataCollector @splatWhatIf)
        }

        It "Should emit no result objects" {
            $whatIfResults.Count | Should -Be 0
        }

        It "Should not create the collection set on the destination" {
            # The absence assertion is the point of the leg: every ShouldProcess branch in the
            # command wraps a write, so a preview that reached one would leave a row here.
            $landedSets = $destServer.Query("SELECT COUNT(*) AS Total FROM msdb.dbo.syscollector_collection_sets WHERE name = N'$collectionSetName'")
            $landedSets.Total | Should -Be 0
        }
    }

    Context "When copying a collection set" {
        BeforeEach {
            $destServer.Query($dropSetSql)
        }

        It "Should create the collection set on the destination" {
            $splatCopy = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                CollectionSet = $collectionSetName
                WarningAction = "SilentlyContinue"
            }
            $copyResults = @(Copy-DbaDataCollector @splatCopy)

            $landedSets = $destServer.Query("SELECT COUNT(*) AS Total FROM msdb.dbo.syscollector_collection_sets WHERE name = N'$collectionSetName'")
            $landedSets.Total | Should -Be 1

            $setStatuses = @($copyResults | Where-Object { $PSItem.Type -eq "Collection Set" })
            $setStatuses.Name | Should -Be @($collectionSetName, $collectionSetName)
        }

        It "Should report the create and the start against one shared status object" {
            # Measured behaviour, not intent. The command builds ONE status object per collection
            # set and emits it twice - once after the create and once after the start - so by the
            # time the pipeline is read both entries show the second status. A port that built a
            # fresh object per emission would report "Successful" then "Successful started
            # Collection" and red here. The null in front of them is the create's unsuppressed
            # $destServer.Query result set.
            $splatShared = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                CollectionSet = $collectionSetName
                WarningAction = "SilentlyContinue"
            }
            $sharedResults = @(Copy-DbaDataCollector @splatShared)

            # Asserted by position: the row the create leaks is a DataRow under Windows PowerShell
            # and carries none of the status properties, so it can only be identified by where it
            # sits in the stream. Four objects for one collection set is the count that reds if a
            # port suppresses the create's result set.
            $sharedResults.Count | Should -Be 4
            $sharedResults[0].Type | Should -Be "Data Collection Server Config"
            $sharedResults[1].Type | Should -BeNullOrEmpty
            $sharedResults[2].Status | Should -Be "Successful started Collection"
            $sharedResults[3].Status | Should -Be "Successful started Collection"
        }

        It "Should skip a collection set that already exists" {
            $splatSeed = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                CollectionSet = $collectionSetName
                WarningAction = "SilentlyContinue"
            }
            $null = Copy-DbaDataCollector @splatSeed

            $splatSkip = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                CollectionSet = $collectionSetName
                WarningAction = "SilentlyContinue"
            }
            $skipResults = @(Copy-DbaDataCollector @splatSkip)

            $setStatuses = @($skipResults | Where-Object { $PSItem.Type -eq "Collection Set" })
            $setStatuses.Count | Should -Be 1
            $setStatuses[0].Status | Should -Be "Skipped"
            $setStatuses[0].Notes | Should -Be "Already exists on destination"
        }

        It "Should drop and recreate an existing collection set with -Force" {
            $splatSeed = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                CollectionSet = $collectionSetName
                WarningAction = "SilentlyContinue"
            }
            $null = Copy-DbaDataCollector @splatSeed
            $seededId = $destServer.Query("SELECT collection_set_id AS Id FROM msdb.dbo.syscollector_collection_sets WHERE name = N'$collectionSetName'").Id

            $splatForce = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                CollectionSet = $collectionSetName
                Force         = $true
                WarningAction = "SilentlyContinue"
            }
            $forceResults = @(Copy-DbaDataCollector @splatForce)

            $setStatuses = @($forceResults | Where-Object { $PSItem.Type -eq "Collection Set" })
            $setStatuses.Count | Should -Be 2
            $setStatuses[0].Status | Should -Be "Successful started Collection"

            # A new collection_set_id is what proves the drop and the recreate both happened - the
            # row count alone is satisfied by a -Force that quietly did nothing.
            $recreatedId = $destServer.Query("SELECT collection_set_id AS Id FROM msdb.dbo.syscollector_collection_sets WHERE name = N'$collectionSetName'").Id
            $recreatedId | Should -Not -Be $seededId
        }
    }

    Context "When copying to more than one destination in one call" {
        BeforeAll {
            $destServer.Query($dropSetSql)

            # The cross-record leg. The placeholder server-config status is emitted once per
            # destination, but the same branch latches $NoServerReconfig to true on its way out and
            # nothing ever resets it, so the second destination in the same call silently loses its
            # object. Only a multi-record call can see that. InstanceCopy1 is the second
            # destination on purpose: it already holds the set as the source, so it reports Skipped
            # and writes nothing, which keeps the leg non-destructive.
            $splatTwoDestinations = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = @($TestConfig.InstanceCopy2, $TestConfig.InstanceCopy1)
                CollectionSet = $collectionSetName
                WarningAction = "SilentlyContinue"
            }
            $twoDestinationResults = @(Copy-DbaDataCollector @splatTwoDestinations)
        }

        It "Should emit the server config placeholder for only the first destination" {
            $configStatuses = @($twoDestinationResults | Where-Object { $PSItem.Type -eq "Data Collection Server Config" })
            $configStatuses.Count | Should -Be 1
            $configStatuses[0].DestinationServer | Should -Be $destServer.Name
        }

        It "Should still process the second destination" {
            $secondDestinationStatuses = @($twoDestinationResults | Where-Object { $PSItem.Type -eq "Collection Set" -and $PSItem.DestinationServer -eq $sourceServer.Name })
            $secondDestinationStatuses.Count | Should -Be 1
            $secondDestinationStatuses[0].Status | Should -Be "Skipped"
        }
    }

    Context "When suppressing the server config placeholder" {
        BeforeAll {
            $destServer.Query($dropSetSql)

            $splatNoReconfig = @{
                Source           = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                CollectionSet    = $collectionSetName
                NoServerReconfig = $true
                WarningAction    = "SilentlyContinue"
            }
            $noReconfigResults = @(Copy-DbaDataCollector @splatNoReconfig)
        }

        It "Should emit no server config placeholder" {
            @($noReconfigResults | Where-Object { $PSItem.Type -eq "Data Collection Server Config" }).Count | Should -Be 0
        }

        It "Should still copy the collection set" {
            $landedSets = $destServer.Query("SELECT COUNT(*) AS Total FROM msdb.dbo.syscollector_collection_sets WHERE name = N'$collectionSetName'")
            $landedSets.Total | Should -Be 1
        }
    }

    Context "When filtering collection sets" {
        BeforeEach {
            $destServer.Query($dropSetSql)
        }

        It "Should copy nothing when -CollectionSet matches no set" {
            $splatMiss = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                CollectionSet = "dbatoolsci_dc_nosuchset"
                WarningAction = "SilentlyContinue"
            }
            $missResults = @(Copy-DbaDataCollector @splatMiss)

            @($missResults | Where-Object { $PSItem.Type -eq "Collection Set" }).Count | Should -Be 0
            $destServer.Query("SELECT COUNT(*) AS Total FROM msdb.dbo.syscollector_collection_sets WHERE name = N'$collectionSetName'").Total | Should -Be 0
        }

        It "Should skip the named set when -ExcludeCollectionSet names it" {
            # No -CollectionSet, so every other non-system source set is in scope. Re-check that
            # there are none before the call rather than trusting the BeforeAll precondition: the
            # source is shared, and a set another window created since would be copied by this leg.
            $foreignSourceSetNames = @($sourceServer.Query($listUserSetsSql) | Select-Object -ExpandProperty name) |
                Where-Object { $PSItem -ne $collectionSetName }
            @($foreignSourceSetNames).Count | Should -Be 0 -Because "an unfiltered copy would carry a foreign collection set to the destination"

            $beforeExcludeSetNames = @($destServer.Query($listUserSetsSql) | Select-Object -ExpandProperty name)

            $splatExclude = @{
                Source               = $TestConfig.InstanceCopy1
                Destination          = $TestConfig.InstanceCopy2
                ExcludeCollectionSet = $collectionSetName
                WarningAction        = "SilentlyContinue"
            }
            $excludeResults = @(Copy-DbaDataCollector @splatExclude)

            @($excludeResults | Where-Object { $PSItem.Name -eq $collectionSetName }).Count | Should -Be 0
            $destServer.Query("SELECT COUNT(*) AS Total FROM msdb.dbo.syscollector_collection_sets WHERE name = N'$collectionSetName'").Total | Should -Be 0

            # With the excluded set the only one on the source, nothing may cross at all. Asserting
            # the diff is empty is stronger than reconciling it against the reported names, and it
            # leaves nothing for this leg to delete - the earlier shape dropped whatever the diff
            # turned up, which on a shared destination means dropping a set another window had just
            # created.
            $afterExcludeSetNames = @($destServer.Query($listUserSetsSql) | Select-Object -ExpandProperty name)
            $addedSetNames = @($afterExcludeSetNames | Where-Object { $PSItem -notin $beforeExcludeSetNames })
            $addedSetNames | Should -Not -Contain $collectionSetName
            @($addedSetNames).Count | Should -Be 0
        }
    }

    Context "When the destination collector is not enabled" {
        # The positive control for every live leg above. The command abandons a destination whose
        # store reports Enabled false, so if the fixture ever stopped enabling the collector the
        # copy legs would keep passing on absence assertions and prove nothing. This leg turns the
        # collector off, shows the copy stops, and turns it back on.
        BeforeAll {
            $destServer.Query($dropSetSql)
            $destServer.Query("IF (SELECT CAST(parameter_value AS int) FROM msdb.dbo.syscollector_config_store WHERE parameter_name = 'CollectorEnabled') = 1 EXEC msdb.dbo.sp_syscollector_disable_collector")
            try {
                $splatDisabled = @{
                    Source        = $TestConfig.InstanceCopy1
                    Destination   = $TestConfig.InstanceCopy2
                    CollectionSet = $collectionSetName
                    WarningAction = "SilentlyContinue"
                }
                $disabledResults = @(Copy-DbaDataCollector @splatDisabled)
                $disabledLandedSets = $destServer.Query("SELECT COUNT(*) AS Total FROM msdb.dbo.syscollector_collection_sets WHERE name = N'$collectionSetName'").Total
            } finally {
                $destServer.Query("IF (SELECT CAST(parameter_value AS int) FROM msdb.dbo.syscollector_config_store WHERE parameter_name = 'CollectorEnabled') = 0 EXEC msdb.dbo.sp_syscollector_enable_collector")
            }
        }

        It "Should copy no collection set" {
            @($disabledResults | Where-Object { $PSItem.Type -eq "Collection Set" }).Count | Should -Be 0
            $disabledLandedSets | Should -Be 0
        }

        It "Should still emit the server config placeholder" {
            @($disabledResults | Where-Object { $PSItem.Type -eq "Data Collection Server Config" }).Count | Should -Be 1
        }
    }

    Context "Guarding on a non-Windows platform" {
        It "Warns and returns nothing when the host is not Windows" {
            InModuleScope dbatools {
                # [char]39 supplies the apostrophe the source message contains (the contraction of
                # "we are") without a literal apostrophe in the test source
                $q = [char]39
                $originalIsWindows = $script:isWindows
                try {
                    $script:isWindows = $false
                    $splatNonWindows = @{
                        Source          = "dbatoolsci-src"
                        Destination     = "dbatoolsci-dst"
                        WarningVariable = "warn"
                        WarningAction   = "SilentlyContinue"
                        WhatIf          = $true
                    }
                    $result = @(Copy-DbaDataCollector @splatNonWindows)
                    $result.Count | Should -Be 0
                    $warn.Count | Should -Be 1

                    # strip the bracketed [timestamp]/[function] prefix added by Write-Message
                    $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
                    $payload | Should -Be "Copy-DbaDataCollector does not support Linux - we${q}re still waiting for the Core SMOs from Microsoft"
                } finally {
                    $script:isWindows = $originalIsWindows
                }
            }
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
            } else {
                # DirectorySecurity is Windows-only and throws PlatformNotSupportedException
                # everywhere else. A directory created fresh under the default umask is already not
                # writable by other users, which is the property this needs - nobody else can drop a
                # replacement resolve.ps1 in between the write and the run.
                $probeDirectoryInfo.Create()
            }
            $probePath = Join-Path -Path $probeDirectory -ChildPath "resolve.ps1"

            # Get-Command -All so a retired function shadowing the cmdlet shows up as a second
            # entry rather than silently winning; the count is what proves it is not there.
            $probeBody = @"
Import-Module -Name "$moduleBase\dbatools.psm1" -DisableNameChecking
`$resolved = Get-Command -Name Copy-DbaDataCollector -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaDataCollector"
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

            $probeArguments = @("-NoProfile", "-NonInteractive", "-File", $probePath)
            $probeOutput = & $shellPath @probeArguments 2>&1
            $probeFields = @("$(@($probeOutput | Where-Object { "$PSItem" -like "RESOLVED|*" })[0])" -split "\|")
        }

        AfterAll {
            $splatRemoveProbeDirectory = @{
                Path        = $probeDirectory
                Recurse     = $true
                Force       = $true
                ErrorAction = "SilentlyContinue"
            }
            Remove-Item @splatRemoveProbeDirectory
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
