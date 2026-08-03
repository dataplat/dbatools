#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDbQueryStoreOption",
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
                "SourceDatabase",
                "Destination",
                "DestinationSqlCredential",
                "DestinationDatabase",
                "Exclude",
                "AllDatabases",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should accept pipeline input on Source, SourceDatabase and Destination" {
            # Three parameters take pipeline input, which is why the connection the begin block
            # opens is made from an unbound -Source on a piped call. Losing any of the three would
            # change which of them a piped object binds to.
            $commandParameters = (Get-Command $CommandName).Parameters
            foreach ($parameterName in "Source", "SourceDatabase", "Destination") {
                $commandParameters[$parameterName].Attributes.Where{ $PSItem -is [System.Management.Automation.ParameterAttribute] }.ValueFromPipeline | Should -Contain $true
            }
            $commandParameters["DestinationDatabase"].Attributes.Where{ $PSItem -is [System.Management.Automation.ParameterAttribute] }.ValueFromPipeline | Should -Not -Contain $true
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When copying Query Store options" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $sourceInstance = $TestConfig.InstanceCopy1
            $destInstance = $TestConfig.InstanceCopy2

            # A GUID rather than Get-Random: these names are dropped in AfterAll, and a 32-bit
            # collision would drop a database a concurrent window created.
            $fixtureStem = "dbatoolsci_qs_$([guid]::NewGuid().ToString("N"))"
            $sourceDbName = "${fixtureStem}_src"
            $sourceAltDbName = "${fixtureStem}_srcalt"
            $destSourceDbName = "${fixtureStem}_destsrc"
            $destDb1Name = "${fixtureStem}_dest1"
            $destDb2Name = "${fixtureStem}_dest2"

            $sourceDb = New-DbaDatabase -SqlInstance $sourceInstance -Name $sourceDbName
            $sourceAltDb = New-DbaDatabase -SqlInstance $sourceInstance -Name $sourceAltDbName
            $destSourceDb = New-DbaDatabase -SqlInstance $destInstance -Name $destSourceDbName
            $destDb1 = New-DbaDatabase -SqlInstance $destInstance -Name $destDb1Name
            $destDb2 = New-DbaDatabase -SqlInstance $destInstance -Name $destDb2Name

            $sourceCustomExecutionCount = 77
            $destPreCustomExecutionCount = 42

            # Pre-seeded on the destination so the version-branch leg reads a known state rather
            # than whatever this instance's defaults happen to be today.
            $splatDest1Options = @{
                SqlInstance                       = $destInstance
                Database                          = $destDb1Name
                State                             = "ReadWrite"
                CaptureMode                       = "Custom"
                CustomCapturePolicyExecutionCount = $destPreCustomExecutionCount
            }
            $null = Set-DbaDbQueryStoreOption @splatDest1Options
            $destDb1PreOptions = Get-DbaDbQueryStoreOption -SqlInstance $destInstance -Database $destDb1Name

            # Derived from what the destination actually holds, not from constants: a hand-picked
            # number that happens to match the destination's current value would leave the copy
            # assertions unable to fail. Offsets keep them distinct by construction.
            $sourceFlushInterval = $destDb1PreOptions.DataFlushIntervalInSeconds + 87
            $sourceMaxPlansPerQuery = $destDb1PreOptions.MaxPlansPerQuery + 7

            $splatSourceOptions = @{
                SqlInstance          = $sourceInstance
                Database             = $sourceDbName
                State                = "ReadWrite"
                FlushInterval        = $sourceFlushInterval
                MaxPlansPerQuery     = $sourceMaxPlansPerQuery
                WaitStatsCaptureMode = "ON"
            }
            $null = Set-DbaDbQueryStoreOption @splatSourceOptions

            # The >= 15 branch is the only one that carries the custom capture policy, and the
            # policy values are only settable while the capture mode is Custom.
            $splatDestSourceOptions = @{
                SqlInstance                       = $destInstance
                Database                          = $destSourceDbName
                State                             = "ReadWrite"
                CaptureMode                       = "Custom"
                CustomCapturePolicyExecutionCount = $sourceCustomExecutionCount
            }
            $null = Set-DbaDbQueryStoreOption @splatDestSourceOptions

            $sourceServerVersion = (Connect-DbaInstance -SqlInstance $sourceInstance).VersionMajor
            $destServerVersion = (Connect-DbaInstance -SqlInstance $destInstance).VersionMajor

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Independent restores: one failure must not strand the databases the later steps drop.
            $cleanupFailures = @()

            try {
                $null = Set-DbaDbState -SqlInstance $destInstance -Database $destDb2Name -Online -Force -ErrorAction SilentlyContinue
            } catch {
                $cleanupFailures += "bringing $destDb2Name online: $PSItem"
            }

            try {
                $null = Remove-DbaDatabase -SqlInstance $sourceInstance -Database $sourceDbName, $sourceAltDbName
            } catch {
                $cleanupFailures += "dropping the source fixtures: $PSItem"
            }

            try {
                $null = Remove-DbaDatabase -SqlInstance $destInstance -Database $destSourceDbName, $destDb1Name, $destDb2Name
            } catch {
                $cleanupFailures += "dropping the destination fixtures: $PSItem"
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            if ($cleanupFailures.Count -gt 0) {
                throw "Fixture cleanup left the lab dirty: $($cleanupFailures -join " | ")"
            }
        }

        It "Should copy the source settings and, on a 2017 source, leave the 2019-only policy alone" {
            $splatCopy = @{
                Source              = $sourceInstance
                SourceDatabase      = $sourceDbName
                Destination         = $destInstance
                DestinationDatabase = $destDb1Name
            }
            $copyResults = @(Copy-DbaDbQueryStoreOption @splatCopy)

            $copyResults.Count | Should -Be 1
            $copyResults[0].Status | Should -Be "Successful"
            $copyResults[0].Type | Should -Be "QueryStore Configuration"
            $copyResults[0].SourceDatabase | Should -Be $sourceDbName
            $copyResults[0].SourceDatabaseID | Should -Be $sourceDb.ID
            $copyResults[0].Name | Should -Be $destDb1Name
            $copyResults[0].DestinationDatabaseID | Should -Be $destDb1.ID

            $destOptions = Get-DbaDbQueryStoreOption -SqlInstance $destInstance -Database $destDb1Name
            $destOptions.DataFlushIntervalInSeconds | Should -Be $sourceFlushInterval

            # MaxPlansPerQuery is exactly what the 2017 branch adds over the 2016 one, so a port
            # that fell into the 2016 branch would leave it at the pre-copy value. That value is
            # read off this database rather than assumed, so the two cannot coincide.
            $destDb1PreOptions.MaxPlansPerQuery | Should -Not -Be $sourceMaxPlansPerQuery
            $destOptions.MaxPlansPerQuery | Should -Be $sourceMaxPlansPerQuery
            $destOptions.WaitStatsCaptureMode | Should -Be "On"

            # The branch is chosen off the SOURCE version, so a 2017 source sends the capture mode
            # it has and the destination's Custom policy goes with it - the values are only
            # readable while the mode is Custom, which is why they come back empty rather than
            # keeping the pre-seeded number.
            $sourceServerVersion | Should -Be 14
            $destServerVersion | Should -BeGreaterOrEqual 15
            $destDb1PreOptions.QueryCaptureMode | Should -Be "Custom"
            $destOptions.QueryCaptureMode | Should -Be "All"
        }

        It "Should carry the custom capture policy when the source is 2019 or higher" {
            $splatCopyV15 = @{
                Source              = $destInstance
                SourceDatabase      = $destSourceDbName
                Destination         = $destInstance
                DestinationDatabase = $destDb2Name
            }
            $v15Results = @(Copy-DbaDbQueryStoreOption @splatCopyV15)

            $v15Results.Count | Should -Be 1
            $v15Results[0].Status | Should -Be "Successful"

            $destOptions = Get-DbaDbQueryStoreOption -SqlInstance $destInstance -Database $destDb2Name
            $destOptions.CustomCapturePolicyExecutionCount | Should -Be $sourceCustomExecutionCount
        }

        It "Should emit nothing and change nothing under -WhatIf" {
            $preOptions = Get-DbaDbQueryStoreOption -SqlInstance $destInstance -Database $destDb2Name

            $splatWhatIf = @{
                Source              = $sourceInstance
                SourceDatabase      = $sourceDbName
                Destination         = $destInstance
                DestinationDatabase = $destDb2Name
                WhatIf              = $true
            }
            $whatIfResults = @(Copy-DbaDbQueryStoreOption @splatWhatIf)

            $whatIfResults | Should -BeNullOrEmpty

            $postOptions = Get-DbaDbQueryStoreOption -SqlInstance $destInstance -Database $destDb2Name
            $postOptions.DataFlushIntervalInSeconds | Should -Be $preOptions.DataFlushIntervalInSeconds
            $postOptions.MaxPlansPerQuery | Should -Be $preOptions.MaxPlansPerQuery
        }

        It "Should copy a database onto itself, because the same-database skip cannot fire" {
            # Pinned to the MEASURED behaviour, not the intended one. The skip compares
            # $sourceServer.Name - a string - against the destination SERVER OBJECT, and an SMO
            # Server stringifies with brackets ("[sql2019]"), so the first half of the conjunction
            # is always false and the guard is unreachable. A port that "fixed" it would emit
            # nothing here and red this leg.
            $splatSelfCopy = @{
                Source              = $destInstance
                SourceDatabase      = $destSourceDbName
                Destination         = $destInstance
                DestinationDatabase = $destSourceDbName
            }
            $selfResults = @(Copy-DbaDbQueryStoreOption @splatSelfCopy -WarningAction SilentlyContinue)

            $selfResults.Count | Should -Be 1
            $selfResults[0].Name | Should -Be $destSourceDbName
            $selfResults[0].SourceDatabase | Should -Be $destSourceDbName
            $selfResults[0].Status | Should -Be "Successful"
        }

        It "Should warn when no database selection parameter is supplied" {
            $splatNoSelection = @{
                Source          = $sourceInstance
                SourceDatabase  = $sourceDbName
                Destination     = $destInstance
                WarningAction   = "SilentlyContinue"
                WarningVariable = "noSelectionWarning"
            }
            $noSelectionResults = @(Copy-DbaDbQueryStoreOption @splatNoSelection)

            $noSelectionResults | Should -BeNullOrEmpty
            $noSelectionWarning | Should -Match "You must specify databases to execute against"
        }

        It "Should warn when the named destination database does not exist" {
            $splatNoMatch = @{
                Source              = $sourceInstance
                SourceDatabase      = $sourceDbName
                Destination         = $destInstance
                DestinationDatabase = "${fixtureStem}_absent"
                WarningAction       = "SilentlyContinue"
                WarningVariable     = "noMatchWarning"
            }
            $noMatchResults = @(Copy-DbaDbQueryStoreOption @splatNoMatch)

            $noMatchResults | Should -BeNullOrEmpty
            $noMatchWarning | Should -Match "No matching databases found"
        }

        It "Should default to every user database, with -Exclude subtracting from that set" {
            # The destination set starts as every non-system database on the instance, so the only
            # safe way to exercise the unfiltered path on a shared lab is to exclude everything
            # this run did not create. Re-read immediately before the call so a database another
            # window created in the meantime is still excluded.
            $strangerDatabases = @(Get-DbaDatabase -SqlInstance $destInstance -ExcludeSystem |
                    Where-Object { $PSItem.Name -notin $destSourceDbName, $destDb1Name, $destDb2Name } |
                    Select-Object -ExpandProperty Name)

            $splatExclude = @{
                Source         = $sourceInstance
                SourceDatabase = $sourceDbName
                Destination    = $destInstance
                Exclude        = $strangerDatabases
            }
            $excludeResults = @(Copy-DbaDbQueryStoreOption @splatExclude)

            # Exactly the three fixtures and nothing else: a stranger database that slipped past
            # the exclusion reds this, rather than being quietly reconfigured.
            @($excludeResults.Name | Sort-Object) | Should -Be @($destSourceDbName, $destDb1Name, $destDb2Name | Sort-Object)
            $excludeResults.Status | Should -Not -Contain "Failed"
            $excludeResults.Status | Should -Not -Contain "Skipped"

            $destOptions = Get-DbaDbQueryStoreOption -SqlInstance $destInstance -Database $destDb2Name
            $destOptions.DataFlushIntervalInSeconds | Should -Be $sourceFlushInterval
        }

        It "Should accept -AllDatabases as the database selection" {
            $strangerDatabases = @(Get-DbaDatabase -SqlInstance $destInstance -ExcludeSystem |
                    Where-Object { $PSItem.Name -notin $destSourceDbName, $destDb1Name, $destDb2Name } |
                    Select-Object -ExpandProperty Name)

            # -AllDatabases is read only by the selection guard: the destination set is already
            # every non-system database before any switch is consulted, so this must produce the
            # same result set as the -Exclude leg above.
            $splatAllDatabases = @{
                Source         = $sourceInstance
                SourceDatabase = $sourceDbName
                Destination    = $destInstance
                Exclude        = $strangerDatabases
                AllDatabases   = $true
            }
            $allResults = @(Copy-DbaDbQueryStoreOption @splatAllDatabases)

            @($allResults.Name | Sort-Object) | Should -Be @($destSourceDbName, $destDb1Name, $destDb2Name | Sort-Object)
            $allResults.Status | Should -Not -Contain "Failed"
        }

        It "Should emit nothing at all when the destination write fails" {
            # By now the -Exclude leg has copied the 2017 source's capture mode (All) onto every
            # fixture, so a 2019-source copy takes the >= 15 branch and hands
            # Set-DbaDbQueryStoreOption null custom-capture-policy values, which it rejects. The
            # catch sets Status "Failed" and then never emits the object, so the caller sees an
            # empty result set rather than the Failed row .OUTPUTS documents. Pinned as measured.
            $splatFailing = @{
                Source              = $destInstance
                SourceDatabase      = $destSourceDbName
                Destination         = $destInstance
                DestinationDatabase = $destDb1Name
            }
            $failingResults = @(Copy-DbaDbQueryStoreOption @splatFailing -WarningAction SilentlyContinue)

            $failingResults | Should -BeNullOrEmpty

            $sourceOptions = Get-DbaDbQueryStoreOption -SqlInstance $destInstance -Database $destSourceDbName
            $sourceOptions.QueryCaptureMode | Should -Not -Be "Custom" -Because "the null policy values that make the write fail only arise once the capture mode has moved off Custom"
        }

        It "Should report Skipped for a destination database that is not accessible" {
            $null = Set-DbaDbState -SqlInstance $destInstance -Database $destDb2Name -Offline -Force

            try {
                $splatOffline = @{
                    Source              = $sourceInstance
                    SourceDatabase      = $sourceDbName
                    Destination         = $destInstance
                    DestinationDatabase = $destDb2Name
                }
                $offlineResults = @(Copy-DbaDbQueryStoreOption @splatOffline)

                $offlineResults.Count | Should -Be 1
                $offlineResults[0].Status | Should -Be "Skipped"
                $offlineResults[0].Name | Should -Be $destDb2Name
            } finally {
                $null = Set-DbaDbState -SqlInstance $destInstance -Database $destDb2Name -Online -Force
            }
        }

        It "Should re-enumerate the destination databases for every destination in one call" {
            # Two instances in ONE call. The destination database list is built inside the
            # per-destination loop, so a port that hoisted it would either report the first
            # instance's database twice or find nothing on the second.
            $splatTwoDestinations = @{
                Source              = $sourceInstance
                SourceDatabase      = $sourceDbName
                Destination         = $destInstance, $sourceInstance
                DestinationDatabase = $destDb1Name, $sourceAltDbName
                WarningAction       = "SilentlyContinue"
            }
            $crossResults = @(Copy-DbaDbQueryStoreOption @splatTwoDestinations)

            $crossResults.Count | Should -Be 2
            $crossResults[0].Name | Should -Be $destDb1Name
            $crossResults[1].Name | Should -Be $sourceAltDbName
            $crossResults[0].Status | Should -Be "Successful"
            $crossResults[1].Status | Should -Be "Successful"
            "$($crossResults[0].DestinationServer)" | Should -Not -Be "$($crossResults[1].DestinationServer)"

            $altOptions = Get-DbaDbQueryStoreOption -SqlInstance $sourceInstance -Database $sourceAltDbName
            $altOptions.DataFlushIntervalInSeconds | Should -Be $sourceFlushInterval
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
            # with CreateNew rather than written over whatever is at the path.
            $probeDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-resolve-$([guid]::NewGuid().ToString("N"))"
            # A GUID makes this unreachable in practice, but every create-directory API below
            # succeeds silently on a path that already exists and leaves its permissions alone, so
            # the one thing that must not happen is adopting somebody else's directory and
            # executing a script out of it.
            if (Test-Path -LiteralPath $probeDirectory) {
                throw "$probeDirectory already exists - this run will not execute a script out of a directory it did not create"
            }
            # Only a directory this block actually created may be deleted in AfterAll. Without the
            # flag the throw above hands the cleanup a path it just refused to touch.
            $probeDirectoryCreated = $false
            $probeDirectoryInfo = New-Object System.IO.DirectoryInfo($probeDirectory)
            if ([System.Environment]::OSVersion.Platform -eq "Win32NT") {
                # The running identity owns it, not Administrators: only an elevated run can hand
                # ownership to a group it is not in, and a descriptor that omits the creator locks
                # the creator out of the directory it just made.
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
                # edition: .NET Framework has DirectoryInfo.Create(DirectorySecurity), .NET moved
                # it out to FileSystemAclExtensions. Probing for the overload rather than the
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
                # everywhere else, so the mode carries the same job there. mkdir rather than a .NET
                # call, for the exclusivity: every managed create-directory API succeeds silently
                # on a directory that already exists and leaves its permissions alone.
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
`$resolved = Get-Command -Name Copy-DbaDbQueryStoreOption -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaDbQueryStoreOption"
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
