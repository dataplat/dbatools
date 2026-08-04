#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaInstanceTrigger",
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
                "ServerTrigger",
                "ExcludeServerTrigger",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # A server trigger is ON ALL SERVER and these instances are shared, so the fixture fires on
    # ALTER_ENDPOINT - an event nothing else here raises - and its body is a bare PRINT. A LOGON
    # trigger would be the obvious choice and is the wrong one: a bad one locks the instance out
    # for every session on it.
    #
    # Every leg names the triggers it wants through -ServerTrigger. Copying the whole source
    # collection would be shorter and would also drag any trigger a neighbouring session left on
    # the source across to the destination.
    #
    # Unlike the Copy-DbaInstanceAudit siblings, the call that runs each batch here is piped to
    # Out-Null, so nothing stray reaches the pipeline and one processed trigger means exactly one
    # result object. That is asserted rather than assumed - it is the difference between a count of
    # one and a count of two in every leg below.
    BeforeAll {
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException

        $triggerOne = "dbatoolsci_servertrigger_one"
        $triggerTwo = "dbatoolsci_servertrigger_two"
        # Its body carries the literal "CREATE " that the command's batch splitter looks for. See
        # the leg that copies it for why that matters.
        $triggerSplit = "dbatoolsci_servertrigger_split"
        $triggerNames = $triggerOne, $triggerTwo, $triggerSplit

        # The source and destination definitions of $triggerOne differ on purpose. Both branches of
        # the already-exists test read the body back, so "left alone" and "dropped and recreated
        # from the source" are told apart by which body is on the destination afterwards - a name
        # check alone passes either way.
        $sourceMarker = "source trigger one"
        $destinationMarker = "destination trigger one"

        function Remove-TestServerTrigger {
            param(
                $Server,
                $Name
            )
            $Server.Triggers.Refresh()
            $leftover = $Server.Triggers[$Name]
            if ($leftover) {
                $leftover.Drop()
            }
            $Server.Triggers.Refresh()
        }

        function New-TestServerTrigger {
            param(
                $Server,
                $Name,
                $Body
            )
            $Server.Query("CREATE TRIGGER [$Name] ON ALL SERVER FOR ALTER_ENDPOINT AS PRINT '$Body'")
            $Server.Triggers.Refresh()
        }

        # Read out of the catalog rather than off the SMO object: the command drops and recreates on
        # its own connection, and this session's Refresh() re-reads the collection without re-reading
        # the module text of an entry whose name did not change - so a replaced trigger keeps serving
        # its old body here.
        function Get-TestServerTriggerDefinition {
            param(
                $Server,
                $Name
            )
            $query = "SELECT m.definition AS Definition FROM sys.server_triggers t JOIN sys.server_sql_modules m ON t.object_id = m.object_id WHERE t.name = N'$Name'"
            return @($Server.Query($query)).Definition
        }

        foreach ($currentServer in $sourceServer, $destServer) {
            foreach ($currentName in $triggerNames) {
                Remove-TestServerTrigger -Server $currentServer -Name $currentName
            }
        }

        New-TestServerTrigger -Server $sourceServer -Name $triggerOne -Body $sourceMarker
        New-TestServerTrigger -Server $sourceServer -Name $triggerTwo -Body "source trigger two"
        New-TestServerTrigger -Server $sourceServer -Name $triggerSplit -Body "CREATE this body breaks"
    }

    AfterAll {
        foreach ($currentServer in $sourceServer, $destServer) {
            foreach ($currentName in $triggerNames) {
                Remove-TestServerTrigger -Server $currentServer -Name $currentName
            }
        }
    }

    Context "When the trigger does not exist on the destination" {
        BeforeEach {
            Remove-TestServerTrigger -Server $destServer -Name $triggerOne
        }

        AfterAll {
            Remove-TestServerTrigger -Server $destServer -Name $triggerOne
        }

        It "Does not create the source trigger on the destination when -WhatIf is used" {
            $destServer.Triggers.Refresh()
            $before = @($destServer.Triggers.Name)
            {
                Copy-DbaInstanceTrigger -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ServerTrigger $triggerOne -WhatIf
            } | Should -Not -Throw
            $destServer.Triggers.Refresh()
            $after = @($destServer.Triggers.Name)
            $after | Should -Be $before
            $after | Should -Not -Contain $triggerOne
        }

        It "Emits no result object under -WhatIf because every status is gated by ShouldProcess" {
            $whatIfResult = Copy-DbaInstanceTrigger -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ServerTrigger $triggerOne -WhatIf
            $whatIfResult | Should -BeNullOrEmpty
        }

        It "Should create the trigger on the destination and report it Successful" {
            # The positive control for both -WhatIf legs above: without it they would pass just as
            # well against a command that copies nothing at all.
            $splatCopyOne = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ServerTrigger = $triggerOne
            }
            $statuses = @(Copy-DbaInstanceTrigger @splatCopyOne)
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $triggerOne
            $statuses[0].Type | Should -Be "Server Trigger"
            $statuses[0].Status | Should -Be "Successful"
            $statuses[0].Notes | Should -BeNullOrEmpty
            $statuses[0].SourceServer | Should -Be $sourceServer.Name
            $statuses[0].DestinationServer | Should -Be $destServer.Name
            $statuses[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"

            $destServer.Triggers.Refresh()
            $destServer.Triggers[$triggerOne] | Should -Not -BeNullOrEmpty
            # The definition travelled, not just the name.
            Get-TestServerTriggerDefinition -Server $destServer -Name $triggerOne | Should -BeLike "*$sourceMarker*"
        }

        It "Should write exactly one object per copied trigger, with nothing stray ahead of it" {
            # The batch calls are piped to Out-Null here. Pinned rather than left implied, because
            # the two nearest sibling commands leave theirs undiscarded and emit a null per batch -
            # legs lifted from those would expect four objects where this one produces one.
            $splatCopyOne = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ServerTrigger = $triggerOne
            }
            $rawResults = @(Copy-DbaInstanceTrigger @splatCopyOne)
            $rawResults.Count | Should -Be 1
            $rawResults[0] | Should -Not -BeNullOrEmpty
            $rawResults[0].Status | Should -Be "Successful"
        }
    }

    Context "When the scripted definition is split into batches" {
        BeforeEach {
            Remove-TestServerTrigger -Server $destServer -Name $triggerSplit
        }

        AfterAll {
            Remove-TestServerTrigger -Server $destServer -Name $triggerSplit
        }

        It "Should fail on a trigger whose body contains the word the splitter cuts on" {
            # This is what proves the copy runs as several batches rather than one. The command
            # rewrites every "CREATE " in the scripted text to a batch break, unanchored, so the
            # word inside this trigger's body is cut too and the batch that carries it arrives with
            # an unterminated string. A port that sent the script as a single batch could not fail
            # this way - it would fail on CREATE TRIGGER not being first in the batch, and a port
            # that stripped the rewrite entirely would report this copy Successful.
            $splatCopySplit = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ServerTrigger = $triggerSplit
                WarningAction = "SilentlyContinue"
            }
            $statuses = @(Copy-DbaInstanceTrigger @splatCopySplit)
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $triggerSplit
            $statuses[0].Status | Should -Be "Failed"
            $statuses[0].Notes | Should -BeLike "*Unclosed quotation mark*"

            $destServer.Triggers.Refresh()
            @($destServer.Triggers.Name) | Should -Not -Contain $triggerSplit
        }
    }

    Context "When only some triggers are wanted" {
        BeforeEach {
            foreach ($currentName in $triggerOne, $triggerTwo) {
                Remove-TestServerTrigger -Server $destServer -Name $currentName
            }
        }

        AfterAll {
            foreach ($currentName in $triggerOne, $triggerTwo) {
                Remove-TestServerTrigger -Server $destServer -Name $currentName
            }
        }

        It "Should copy only the trigger named in -ServerTrigger" {
            $splatCopyNamed = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ServerTrigger = $triggerTwo
            }
            $statuses = @(Copy-DbaInstanceTrigger @splatCopyNamed)
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $triggerTwo

            $destServer.Triggers.Refresh()
            $destinationNames = @($destServer.Triggers.Name)
            $destinationNames | Should -Contain $triggerTwo
            $destinationNames | Should -Not -Contain $triggerOne
        }

        It "Should skip the trigger named in -ExcludeServerTrigger even when it is also named in -ServerTrigger" {
            # Both filters at once, because the exclusion is the second half of a single condition
            # whose first half is the -ServerTrigger test - reading -ExcludeServerTrigger alone
            # cannot tell whether the exclusion is applied or merely never contradicted.
            $splatCopyExcluded = @{
                Source               = $TestConfig.InstanceCopy1
                Destination          = $TestConfig.InstanceCopy2
                ServerTrigger        = $triggerOne, $triggerTwo
                ExcludeServerTrigger = $triggerOne
            }
            $statuses = @(Copy-DbaInstanceTrigger @splatCopyExcluded)
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $triggerTwo
            $statuses[0].Status | Should -Be "Successful"

            $destServer.Triggers.Refresh()
            @($destServer.Triggers.Name) | Should -Not -Contain $triggerOne
        }
    }

    Context "When the trigger already exists on the destination" {
        BeforeEach {
            Remove-TestServerTrigger -Server $destServer -Name $triggerOne
            New-TestServerTrigger -Server $destServer -Name $triggerOne -Body $destinationMarker
        }

        AfterAll {
            Remove-TestServerTrigger -Server $destServer -Name $triggerOne
        }

        It "Should report it Skipped and leave the destination definition untouched" {
            $splatCopyExisting = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ServerTrigger = $triggerOne
            }
            $statuses = @(Copy-DbaInstanceTrigger @splatCopyExisting)
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $triggerOne
            $statuses[0].Status | Should -Be "Skipped"
            $statuses[0].Notes | Should -Be "Already exists on destination"

            Get-TestServerTriggerDefinition -Server $destServer -Name $triggerOne | Should -BeLike "*$destinationMarker*"
        }

        It "Emits no result object under -WhatIf on the already-exists path either" {
            # The skip status is written inside its own ShouldProcess, so -WhatIf suppresses the
            # report of a skip just as it suppresses the report of a copy.
            $splatCopyExistingWhatIf = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ServerTrigger = $triggerOne
                WhatIf        = $true
            }
            $whatIfResult = Copy-DbaInstanceTrigger @splatCopyExistingWhatIf
            $whatIfResult | Should -BeNullOrEmpty

            Get-TestServerTriggerDefinition -Server $destServer -Name $triggerOne | Should -BeLike "*$destinationMarker*"
        }

        It "Should replace the destination trigger with the source definition when -Force is used" {
            $splatCopyForced = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ServerTrigger = $triggerOne
                Force         = $true
            }
            $statuses = @(Copy-DbaInstanceTrigger @splatCopyForced)
            $statuses.Count | Should -Be 1
            $statuses[0].Status | Should -Be "Successful"

            $destServer.Triggers.Refresh()
            @($destServer.Triggers.Name) | Should -Contain $triggerOne
            $definition = Get-TestServerTriggerDefinition -Server $destServer -Name $triggerOne
            $definition | Should -BeLike "*$sourceMarker*"
            $definition | Should -Not -BeLike "*$destinationMarker*"
        }
    }

    Context "When one call spans more than one destination" {
        BeforeAll {
            Remove-TestServerTrigger -Server $destServer -Name $triggerTwo
        }

        AfterAll {
            Remove-TestServerTrigger -Server $destServer -Name $triggerTwo
        }

        It "Should reach the second destination after the first one skips" {
            # The source instance is itself the first destination, so its copy takes the
            # already-exists branch. A port that stopped after the first destination would return
            # that skip alone and never create anything on the second.
            $splatCopyBothDestinations = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                ServerTrigger = $triggerTwo
            }
            $statuses = @(Copy-DbaInstanceTrigger @splatCopyBothDestinations)
            $statuses.Count | Should -Be 2
            $statuses[0].DestinationServer | Should -Be $sourceServer.Name
            $statuses[0].Status | Should -Be "Skipped"
            $statuses[1].DestinationServer | Should -Be $destServer.Name
            $statuses[1].Status | Should -Be "Successful"

            $destServer.Triggers.Refresh()
            @($destServer.Triggers.Name) | Should -Contain $triggerTwo
        }
    }

    Context "Unreachable destination" {
        BeforeAll {
            # Scoped to this Context alone, never the whole file: the legs above make real
            # connections and would turn flaky on a slow guest under a 1-second fuse. The pin is
            # needed because the unreachable endpoint is only refused instantly where the port is
            # CLOSED - where it is firewalled the packet is dropped and the leg waits out the
            # 15-second default instead. Restoring in AfterAll is mandatory, the setting being
            # process-wide.
            $previousConnectTimeout = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value 1
        }
        AfterAll {
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value $previousConnectTimeout
        }

        It "Surfaces the destination-connect warning instead of throwing when the destination is unreachable" {
            $connectWarning = $null
            $splatCopyDeadDestination = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceUnreachable
                ServerTrigger   = $triggerOne
                WarningVariable = "connectWarning"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            try {
                $null = Copy-DbaInstanceTrigger @splatCopyDeadDestination
            } catch {
                # an unreachable destination may raise downstream errors; the warning stream is what this test asserts
            }
            $connectWarning | Should -Not -BeNullOrEmpty
        }

        It "Emits no result at all when the source cannot be reached" {
            # The Test-FunctionInterrupt guard ahead of the destination loop: a source that never
            # connected must not reach a destination that is perfectly healthy.
            $splatCopyDeadSource = @{
                Source        = $TestConfig.InstanceUnreachable
                Destination   = $TestConfig.InstanceCopy2
                ServerTrigger = $triggerOne
                WarningAction = "SilentlyContinue"
                ErrorAction   = "SilentlyContinue"
            }
            $results = @(Copy-DbaInstanceTrigger @splatCopyDeadSource)
            $results | Should -BeNullOrEmpty
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
`$resolved = Get-Command -Name Copy-DbaInstanceTrigger -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaInstanceTrigger"
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
