#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaInstanceAuditSpecification",
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
                "AuditSpecification",
                "ExcludeAuditSpecification",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # One shipping quirk shapes the counting in every leg below, and it is pinned deliberately: the
    # call that runs the CREATE batch is neither assigned nor discarded, so its null return is
    # written to the pipeline. Every specification that copies successfully therefore emits a stray
    # $null ahead of its status object, while the two skip branches emit their status alone. That is
    # why the legs filter to the non-null results before asserting on them, and why one leg measures
    # the raw count instead.
    #
    # The two skip branches both emit, unlike some of the sibling Copy-Dba* commands, so a skipped
    # specification is distinguishable from one the filter never reached.
    BeforeAll {
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException

        # SQL Server allows at most one server audit specification per server audit, so every
        # specification in this fixture needs an audit of its own.
        $auditOne = "dbatoolsci_auditspec_one"
        $auditTwo = "dbatoolsci_auditspec_two"
        $auditOrphan = "dbatoolsci_auditspec_orphan"
        $auditNames = $auditOne, $auditTwo, $auditOrphan
        $specOne = "dbatoolsci_spec_one"
        $specTwo = "dbatoolsci_spec_two"
        $specOrphan = "dbatoolsci_spec_orphan"
        $specNames = $specOne, $specTwo, $specOrphan

        # The source and destination definitions of $specOne differ on purpose. Both branches of the
        # already-exists test read the action group back, so "left alone" and "dropped and recreated
        # from the source" are told apart by which group is on the destination afterwards - a name
        # check alone passes either way.
        $sourceActionGroup = "FAILED_LOGIN_GROUP"
        $destinationActionGroup = "SUCCESSFUL_LOGIN_GROUP"

        function Remove-TestAuditSpecification {
            param(
                $Server,
                $Name
            )
            $Server.ServerAuditSpecifications.Refresh()
            $leftover = $Server.ServerAuditSpecifications[$Name]
            if ($leftover) {
                try {
                    $leftover.Disable()
                } catch {
                    # a never-enabled specification cannot be disabled; drop it directly
                }
                $leftover.Drop()
            }
            $Server.ServerAuditSpecifications.Refresh()
        }

        function Remove-TestAudit {
            param(
                $Server,
                $Name
            )
            $Server.Audits.Refresh()
            $leftover = $Server.Audits[$Name]
            if ($leftover) {
                try {
                    $leftover.Disable()
                    $leftover.Alter()
                } catch {
                    # a never-enabled audit cannot be disabled; drop it directly
                }
                $leftover.Drop()
            }
            $Server.Audits.Refresh()
        }

        # Read out of the catalog rather than off the SMO object: the command drops and recreates on
        # its own connection, and this session's Refresh() re-reads the collection without re-reading
        # the detail rows of an entry whose name did not change - so a replaced specification keeps
        # serving its old action group here.
        function Get-TestSpecificationActionGroup {
            param(
                $Server,
                $Name
            )
            $query = "SELECT d.audit_action_name AS ActionName FROM sys.server_audit_specifications s JOIN sys.server_audit_specification_details d ON s.server_specification_id = d.server_specification_id WHERE s.name = N'$Name'"
            return @($Server.Query($query)).ActionName
        }

        function New-TestSpecification {
            param(
                $Server,
                $Name,
                $AuditName,
                $ActionGroup
            )
            $Server.Query("CREATE SERVER AUDIT SPECIFICATION [$Name] FOR SERVER AUDIT [$AuditName] ADD ($ActionGroup)")
            $Server.ServerAuditSpecifications.Refresh()
        }

        # Clean slate on both instances in case a prior run left the fixture behind. A specification
        # must be dropped before the audit it references, so the drop order is spec then audit.
        foreach ($currentServer in $sourceServer, $destServer) {
            foreach ($currentName in $specNames) {
                Remove-TestAuditSpecification -Server $currentServer -Name $currentName
            }
            foreach ($currentName in $auditNames) {
                Remove-TestAudit -Server $currentServer -Name $currentName
            }
        }

        # APPLICATION_LOG target needs no file path, so the fixture is deterministic on any host.
        # $auditOrphan exists on the source only - that is what makes the missing-audit skip branch
        # reachable, since a specification cannot be created against an audit the destination lacks.
        foreach ($currentServer in $sourceServer, $destServer) {
            $currentServer.Query("CREATE SERVER AUDIT [$auditOne] TO APPLICATION_LOG")
            $currentServer.Query("CREATE SERVER AUDIT [$auditTwo] TO APPLICATION_LOG")
            $currentServer.Audits.Refresh()
        }
        $sourceServer.Query("CREATE SERVER AUDIT [$auditOrphan] TO APPLICATION_LOG")
        $sourceServer.Audits.Refresh()

        New-TestSpecification -Server $sourceServer -Name $specOne -AuditName $auditOne -ActionGroup $sourceActionGroup
        New-TestSpecification -Server $sourceServer -Name $specTwo -AuditName $auditTwo -ActionGroup $sourceActionGroup
        New-TestSpecification -Server $sourceServer -Name $specOrphan -AuditName $auditOrphan -ActionGroup $sourceActionGroup
    }

    AfterAll {
        foreach ($currentServer in $sourceServer, $destServer) {
            foreach ($currentName in $specNames) {
                Remove-TestAuditSpecification -Server $currentServer -Name $currentName
            }
            foreach ($currentName in $auditNames) {
                Remove-TestAudit -Server $currentServer -Name $currentName
            }
        }
    }

    Context "When the specification does not exist on the destination" {
        BeforeEach {
            Remove-TestAuditSpecification -Server $destServer -Name $specOne
        }

        AfterAll {
            Remove-TestAuditSpecification -Server $destServer -Name $specOne
        }

        It "Does not create the source specification on the destination when -WhatIf is used" {
            $destServer.ServerAuditSpecifications.Refresh()
            $before = @($destServer.ServerAuditSpecifications.Name)
            {
                Copy-DbaInstanceAuditSpecification -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -AuditSpecification $specOne -WhatIf
            } | Should -Not -Throw
            $destServer.ServerAuditSpecifications.Refresh()
            $after = @($destServer.ServerAuditSpecifications.Name)
            $after | Should -Be $before
            $after | Should -Not -Contain $specOne
        }

        It "Emits no result object under -WhatIf because every status is gated by ShouldProcess" {
            $whatIfResult = Copy-DbaInstanceAuditSpecification -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -AuditSpecification $specOne -WhatIf
            $whatIfResult | Should -BeNullOrEmpty
        }

        It "Should create the specification on the destination and report it Successful" {
            # The positive control for both -WhatIf legs above: without it they would pass just as
            # well against a command that copies nothing at all.
            $splatCopyOne = @{
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceCopy2
                AuditSpecification = $specOne
            }
            $statuses = @(Copy-DbaInstanceAuditSpecification @splatCopyOne | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $specOne
            $statuses[0].Type | Should -Be "Server Audit Specification"
            $statuses[0].Status | Should -Be "Successful"
            $statuses[0].Notes | Should -BeNullOrEmpty
            $statuses[0].SourceServer | Should -Be $sourceServer.Name
            $statuses[0].DestinationServer | Should -Be $destServer.Name
            $statuses[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"

            $destServer.ServerAuditSpecifications.Refresh()
            $destServer.ServerAuditSpecifications[$specOne] | Should -Not -BeNullOrEmpty
            # The definition travelled, not just the name: the source action group is what landed.
            Get-TestSpecificationActionGroup -Server $destServer -Name $specOne | Should -Be $sourceActionGroup
        }

        It "Should write a stray null to the pipeline ahead of the status object" {
            # The undiscarded return of the CREATE batch. Pinned rather than assumed away, because it
            # is the difference between one result per specification and two, and the legs above
            # would have to guess which without it.
            $splatCopyOne = @{
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceCopy2
                AuditSpecification = $specOne
            }
            $rawResults = @(Copy-DbaInstanceAuditSpecification @splatCopyOne)
            $rawResults.Count | Should -Be 2
            $rawResults[0] | Should -BeNullOrEmpty
            $rawResults[1].Status | Should -Be "Successful"
        }
    }

    Context "When only some specifications are wanted" {
        BeforeEach {
            foreach ($currentName in $specOne, $specTwo) {
                Remove-TestAuditSpecification -Server $destServer -Name $currentName
            }
        }

        AfterAll {
            foreach ($currentName in $specOne, $specTwo) {
                Remove-TestAuditSpecification -Server $destServer -Name $currentName
            }
        }

        It "Should copy only the specification named in -AuditSpecification" {
            $splatCopyNamed = @{
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceCopy2
                AuditSpecification = $specTwo
            }
            $statuses = @(Copy-DbaInstanceAuditSpecification @splatCopyNamed | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $specTwo

            $destServer.ServerAuditSpecifications.Refresh()
            $destinationNames = @($destServer.ServerAuditSpecifications.Name)
            $destinationNames | Should -Contain $specTwo
            $destinationNames | Should -Not -Contain $specOne
        }

        It "Should skip the specification named in -ExcludeAuditSpecification" {
            # $specOrphan is excluded alongside $specOne so the only specification left for the
            # command to act on is $specTwo; without that the missing-audit branch would add a second
            # status object and the count below would not discriminate.
            $splatCopyExcluded = @{
                Source                    = $TestConfig.InstanceCopy1
                Destination               = $TestConfig.InstanceCopy2
                ExcludeAuditSpecification = $specOne, $specOrphan
            }
            $statuses = @(Copy-DbaInstanceAuditSpecification @splatCopyExcluded | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $specTwo
            $statuses[0].Status | Should -Be "Successful"

            $destServer.ServerAuditSpecifications.Refresh()
            @($destServer.ServerAuditSpecifications.Name) | Should -Not -Contain $specOne
        }
    }

    Context "When the specification already exists on the destination" {
        BeforeEach {
            Remove-TestAuditSpecification -Server $destServer -Name $specOne
            New-TestSpecification -Server $destServer -Name $specOne -AuditName $auditOne -ActionGroup $destinationActionGroup
        }

        AfterAll {
            Remove-TestAuditSpecification -Server $destServer -Name $specOne
        }

        It "Should report it Skipped and leave the destination definition untouched" {
            $splatCopyExisting = @{
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceCopy2
                AuditSpecification = $specOne
            }
            $statuses = @(Copy-DbaInstanceAuditSpecification @splatCopyExisting | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $specOne
            $statuses[0].Status | Should -Be "Skipped"
            $statuses[0].Notes | Should -Be "Already exists on destination"

            # No stray null on this path - nothing ran a CREATE batch.
            Get-TestSpecificationActionGroup -Server $destServer -Name $specOne | Should -Be $destinationActionGroup
        }

        It "Should replace the destination specification with the source definition when -Force is used" {
            $splatCopyForced = @{
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceCopy2
                AuditSpecification = $specOne
                Force              = $true
            }
            $statuses = @(Copy-DbaInstanceAuditSpecification @splatCopyForced | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 1
            $statuses[0].Status | Should -Be "Successful"

            $destServer.ServerAuditSpecifications.Refresh()
            @($destServer.ServerAuditSpecifications.Name) | Should -Contain $specOne
            Get-TestSpecificationActionGroup -Server $destServer -Name $specOne | Should -Be $sourceActionGroup
        }
    }

    Context "When the audit the specification references is missing on the destination" {
        AfterAll {
            Remove-TestAuditSpecification -Server $destServer -Name $specOrphan
        }

        It "Should report it Skipped, warn, and create nothing" {
            $missingAuditWarning = $null
            $splatCopyOrphan = @{
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceCopy2
                AuditSpecification = $specOrphan
                WarningVariable    = "missingAuditWarning"
                WarningAction      = "SilentlyContinue"
            }
            $statuses = @(Copy-DbaInstanceAuditSpecification @splatCopyOrphan | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $specOrphan
            $statuses[0].Status | Should -Be "Skipped"
            $statuses[0].Notes | Should -BeLike "Audit $auditOrphan does not exist on *. Skipping $specOrphan."

            # This branch is the only skip that also warns, so the warning is what tells it apart
            # from the already-exists skip above.
            "$missingAuditWarning" | Should -BeLike "*Audit $auditOrphan does not exist on *"

            $destServer.ServerAuditSpecifications.Refresh()
            @($destServer.ServerAuditSpecifications.Name) | Should -Not -Contain $specOrphan
        }
    }

    Context "When one call spans more than one destination" {
        BeforeAll {
            Remove-TestAuditSpecification -Server $destServer -Name $specTwo
        }

        AfterAll {
            Remove-TestAuditSpecification -Server $destServer -Name $specTwo
        }

        It "Should reach the second destination after the first one skips" {
            # The source instance is itself the first destination, so its copy takes the
            # already-exists branch. A port that stopped after the first destination would return
            # that skip alone and never create anything on the second.
            $splatCopyBothDestinations = @{
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                AuditSpecification = $specTwo
            }
            $statuses = @(Copy-DbaInstanceAuditSpecification @splatCopyBothDestinations | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 2
            $statuses[0].DestinationServer | Should -Be $sourceServer.Name
            $statuses[0].Status | Should -Be "Skipped"
            $statuses[1].DestinationServer | Should -Be $destServer.Name
            $statuses[1].Status | Should -Be "Successful"

            $destServer.ServerAuditSpecifications.Refresh()
            @($destServer.ServerAuditSpecifications.Name) | Should -Contain $specTwo
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
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceUnreachable
                AuditSpecification = $specOne
                WarningVariable    = "connectWarning"
                WarningAction      = "SilentlyContinue"
                ErrorAction        = "SilentlyContinue"
            }
            try {
                $null = Copy-DbaInstanceAuditSpecification @splatCopyDeadDestination
            } catch {
                # an unreachable destination may raise downstream errors; the warning stream is what this test asserts
            }
            $connectWarning | Should -Not -BeNullOrEmpty
        }

        It "Emits no result at all when the source cannot be reached" {
            # The Test-FunctionInterrupt guard ahead of the destination loop: a source that never
            # connected must not reach a destination that is perfectly healthy.
            $splatCopyDeadSource = @{
                Source             = $TestConfig.InstanceUnreachable
                Destination        = $TestConfig.InstanceCopy2
                AuditSpecification = $specOne
                WarningAction      = "SilentlyContinue"
                ErrorAction        = "SilentlyContinue"
            }
            $results = @(Copy-DbaInstanceAuditSpecification @splatCopyDeadSource)
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
`$resolved = Get-Command -Name Copy-DbaInstanceAuditSpecification -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaInstanceAuditSpecification"
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
