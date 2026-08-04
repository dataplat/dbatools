#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaInstanceAudit",
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
                "Audit",
                "ExcludeAudit",
                "Path",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Two shipping quirks shape every assertion below, and both are pinned deliberately.
    #
    # The already-exists branch sets Status and Notes on its result object and then never emits it,
    # so a run that skipped every audit looks exactly like a run that matched none. Legs that
    # exercise that branch therefore copy a second audit in the same call: the surviving result
    # object is what proves the loop reached both. Audit GUIDs carry the rest of the discrimination
    # - Script() writes AUDIT_GUID, so a copied audit inherits the source GUID while an audit the
    # destination created for itself keeps its own.
    #
    # And the call that runs the CREATE batch is not assigned or discarded, so its null return is
    # written to the pipeline: every audit that copies successfully emits a stray $null ahead of its
    # status object. That is why the legs count the non-null results rather than the raw ones.
    BeforeAll {
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException

        $auditName = "dbatoolsci_audit_base"
        $secondAuditName = "dbatoolsci_audit_second"
        $fileAuditName = "dbatoolsci_audit_file"
        $auditNames = $auditName, $secondAuditName, $fileAuditName

        # The data directory, not the backup directory: both instances back up to the same path, so
        # a -Path leg pointed there would pass just as well without -Path.
        $destinationFilePath = $destServer.MasterDBPath

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
        # its own connection, and this session's Audits.Refresh() re-reads the collection without
        # re-reading the properties of an entry whose name did not change - so a replaced audit
        # keeps serving its old GUID here.
        function Get-TestAuditGuid {
            param(
                $Server,
                $Name
            )
            $guidRows = $Server.Query("SELECT CONVERT(nvarchar(36), audit_guid) AS AuditGuid FROM sys.server_audits WHERE name = N'$Name'")
            return @($guidRows).AuditGuid
        }

        # Clean slate on both instances in case a prior run left the fixture behind.
        foreach ($currentServer in $sourceServer, $destServer) {
            foreach ($currentName in $auditNames) {
                Remove-TestAudit -Server $currentServer -Name $currentName
            }
        }

        # APPLICATION_LOG target needs no file path, so the fixture is deterministic on any host.
        # The one FILE audit exists only for the -Path leg, and its source path is never expected to
        # resolve on the destination.
        $sourceServer.Query("CREATE SERVER AUDIT [$auditName] TO APPLICATION_LOG")
        $sourceServer.Query("CREATE SERVER AUDIT [$secondAuditName] TO APPLICATION_LOG")
        $sourceServer.Query("CREATE SERVER AUDIT [$fileAuditName] TO FILE (FILEPATH = N'$($sourceServer.BackupDirectory)')")
        $sourceServer.Audits.Refresh()
    }

    AfterAll {
        foreach ($currentServer in $sourceServer, $destServer) {
            foreach ($currentName in $auditNames) {
                Remove-TestAudit -Server $currentServer -Name $currentName
            }
        }
    }

    Context "When the audit does not exist on the destination" {
        BeforeAll {
            Remove-TestAudit -Server $destServer -Name $auditName
        }

        AfterAll {
            Remove-TestAudit -Server $destServer -Name $auditName
        }

        It "Does not create the source audit on the destination when -WhatIf is used" {
            $destServer.Audits.Refresh()
            $before = @($destServer.Audits.Name)
            {
                Copy-DbaInstanceAudit -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Audit $auditName -WhatIf
            } | Should -Not -Throw
            $destServer.Audits.Refresh()
            $after = @($destServer.Audits.Name)
            $after | Should -Be $before
            $after | Should -Not -Contain $auditName
        }

        It "Emits no result object under -WhatIf because every status is gated by ShouldProcess" {
            $whatIfResult = Copy-DbaInstanceAudit -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Audit $auditName -WhatIf
            $whatIfResult | Should -BeNullOrEmpty
        }

        It "Should create the audit on the destination and report it Successful" {
            # The positive control for both -WhatIf legs above: without it they would pass against a
            # command that copies nothing at all.
            $results = @(Copy-DbaInstanceAudit -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Audit $auditName)
            $statuses = @($results | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $auditName
            $statuses[0].Type | Should -Be "Server Audit"
            $statuses[0].Status | Should -Be "Successful"
            $statuses[0].SourceServer | Should -Be $sourceServer.Name
            $statuses[0].DestinationServer | Should -Be $destServer.Name

            $destServer.Audits.Refresh()
            $destServer.Audits[$auditName] | Should -Not -BeNullOrEmpty
            Get-TestAuditGuid -Server $destServer -Name $auditName | Should -Be (Get-TestAuditGuid -Server $sourceServer -Name $auditName)
        }

        It "Should write a stray null to the pipeline ahead of the status object" {
            # The undiscarded return of the CREATE batch. Pinned rather than assumed away, because
            # it is the difference between one result per audit and two, and the leg above would
            # have to guess which without it.
            Remove-TestAudit -Server $destServer -Name $auditName
            $results = @(Copy-DbaInstanceAudit -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Audit $auditName)
            $results.Count | Should -Be 2
            $results[0] | Should -BeNullOrEmpty
            $results[1].Status | Should -Be "Successful"
        }
    }

    Context "When only some audits are wanted" {
        BeforeAll {
            foreach ($currentName in $auditName, $secondAuditName) {
                Remove-TestAudit -Server $destServer -Name $currentName
            }
        }

        AfterAll {
            foreach ($currentName in $auditName, $secondAuditName) {
                Remove-TestAudit -Server $destServer -Name $currentName
            }
        }

        It "Should copy only the audit named in -Audit" {
            $splatCopyOne = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Audit       = $auditName
            }
            $statuses = @(Copy-DbaInstanceAudit @splatCopyOne | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $auditName

            $destServer.Audits.Refresh()
            @($destServer.Audits.Name) | Should -Not -Contain $secondAuditName
        }

        It "Should skip the audit named in -ExcludeAudit" {
            $splatCopyExcluded = @{
                Source       = $TestConfig.InstanceCopy1
                Destination  = $TestConfig.InstanceCopy2
                Audit        = $auditName, $secondAuditName
                ExcludeAudit = $auditName
            }
            $results = @(Copy-DbaInstanceAudit @splatCopyExcluded)
            @($results.Name) | Should -Contain $secondAuditName
            @($results.Name) | Should -Not -Contain $auditName
        }
    }

    Context "When the audit already exists on the destination" {
        BeforeAll {
            Remove-TestAudit -Server $destServer -Name $auditName
            Remove-TestAudit -Server $destServer -Name $secondAuditName
            # Created by the destination rather than copied, so it carries its own AUDIT_GUID and a
            # replacement is visible as a GUID change.
            $destServer.Query("CREATE SERVER AUDIT [$auditName] TO APPLICATION_LOG")
            $destServer.Audits.Refresh()
            $sourceServer.Audits.Refresh()
        }

        AfterAll {
            Remove-TestAudit -Server $destServer -Name $auditName
            Remove-TestAudit -Server $destServer -Name $secondAuditName
        }

        It "Should emit nothing for the audit that is already there while still copying the one that is not" {
            $splatCopyBoth = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Audit       = $auditName, $secondAuditName
            }
            $statuses = @(Copy-DbaInstanceAudit @splatCopyBoth | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 1
            $statuses[0].Name | Should -Be $secondAuditName
            $statuses[0].Status | Should -Be "Successful"

            Get-TestAuditGuid -Server $destServer -Name $auditName | Should -Not -Be (Get-TestAuditGuid -Server $sourceServer -Name $auditName)
        }

        It "Should replace the destination audit with the source definition when -Force is used" {
            $beforeGuid = Get-TestAuditGuid -Server $destServer -Name $auditName
            $splatCopyForce = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Audit       = $auditName
                Force       = $true
            }
            $statuses = @(Copy-DbaInstanceAudit @splatCopyForce | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 1
            $statuses[0].Status | Should -Be "Successful"

            $destServer.Audits.Refresh()
            $destServer.Audits[$auditName] | Should -Not -BeNullOrEmpty
            $afterGuid = Get-TestAuditGuid -Server $destServer -Name $auditName
            $afterGuid | Should -Not -Be $beforeGuid
            $afterGuid | Should -Be (Get-TestAuditGuid -Server $sourceServer -Name $auditName)
        }
    }

    Context "When the destination audit directory is given" {
        BeforeAll {
            Remove-TestAudit -Server $destServer -Name $fileAuditName
        }

        AfterAll {
            Remove-TestAudit -Server $destServer -Name $fileAuditName
        }

        It "Should write the destination audit to the path in -Path" {
            $splatCopyPath = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Audit       = $fileAuditName
                Path        = $destinationFilePath
            }
            $statuses = @(Copy-DbaInstanceAudit @splatCopyPath | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 1
            $statuses[0].Status | Should -Be "Successful"

            $destServer.Audits.Refresh()
            $sourceServer.Audits.Refresh()
            $destServer.Audits[$fileAuditName].DestinationType | Should -Be "File"
            $destServer.Audits[$fileAuditName].FilePath.TrimEnd("\") | Should -Be $destinationFilePath.TrimEnd("\")
            $destServer.Audits[$fileAuditName].FilePath.TrimEnd("\") | Should -Not -Be $sourceServer.Audits[$fileAuditName].FilePath.TrimEnd("\")
        }
    }

    Context "When one call spans more than one destination" {
        BeforeAll {
            Remove-TestAudit -Server $destServer -Name $secondAuditName
        }

        AfterAll {
            Remove-TestAudit -Server $destServer -Name $secondAuditName
        }

        It "Should reach the second destination when the first one has nothing to do" {
            # The source instance is itself the first destination, so its copy takes the
            # already-exists branch and emits nothing. A port that stopped after the first
            # destination would therefore return nothing at all rather than one object.
            $splatCopyBothDestinations = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Audit       = $secondAuditName
            }
            $statuses = @(Copy-DbaInstanceAudit @splatCopyBothDestinations | Where-Object { $null -ne $PSItem })
            $statuses.Count | Should -Be 1
            $statuses[0].DestinationServer | Should -Be $destServer.Name
            $statuses[0].Status | Should -Be "Successful"

            $destServer.Audits.Refresh()
            @($destServer.Audits.Name) | Should -Contain $secondAuditName
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
            try {
                $null = Copy-DbaInstanceAudit -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceUnreachable -Audit $auditName -WarningVariable connectWarning -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
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
                Audit         = $auditName
                WarningAction = "SilentlyContinue"
                ErrorAction   = "SilentlyContinue"
            }
            $results = @(Copy-DbaInstanceAudit @splatCopyDeadSource)
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
`$resolved = Get-Command -Name Copy-DbaInstanceAudit -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaInstanceAudit"
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
