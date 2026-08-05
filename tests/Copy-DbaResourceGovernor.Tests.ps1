#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaResourceGovernor",
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
                "ResourcePool",
                "ExcludeResourcePool",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Resource Governor is instance-wide, so every leg here names the pools it wants through
    # -ResourcePool rather than copying the whole source collection - a bare copy would drag any
    # pool a neighbouring session left on the source across to the destination.
    #
    # The catalog views are read directly rather than SMO's ResourceGovernor collection. The command
    # drops and recreates on its own connection, and Refresh() on this session's collection has been
    # seen serving the pre-drop settings of a pool whose name did not change.
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Explain what needs to be set up for the test:
        # To test copying resource governor settings, we need to create resource pools, workload groups, and a classifier function on the source instance.

        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

        # Named separately from the two pools the whole-configuration leg copies, because this one
        # has to be absent from the destination when the -WhatIf legs run and those legs would
        # otherwise be fighting the leg that copies everything.
        $whatIfPool = "dbatoolsci_rgwhatif"
        $whatIfGroup = "dbatoolsci_rgwhatifprocessing"
        $prodPool = "dbatoolsci_prod"
        # A pool with no workload group at all. -Force takes a different path for it than for a
        # pool that has one, and the two outcomes are not the same - see the -Force context below.
        $barePool = "dbatoolsci_rgbare"
        $testPools = $prodPool, "dbatoolsci_offhoursprocessing", $whatIfPool, $barePool

        function Remove-TestResourcePool {
            param(
                $Server,
                $Name
            )
            # Workload groups first - a pool that still has one cannot be dropped.
            $groupQuery = "SELECT g.name AS GroupName FROM sys.resource_governor_workload_groups g JOIN sys.resource_governor_resource_pools p ON g.pool_id = p.pool_id WHERE p.name = N'$Name'"
            foreach ($groupName in @($Server.Query($groupQuery) | Where-Object { $PSItem.GroupName }).GroupName) {
                $Server.Query("DROP WORKLOAD GROUP [$groupName]")
            }
            $Server.Query("IF EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = N'$Name') DROP RESOURCE POOL [$Name]")
            $Server.Query("ALTER RESOURCE GOVERNOR RECONFIGURE")
        }

        function Test-TestResourcePoolExists {
            param(
                $Server,
                $Name
            )
            $rows = @($Server.Query("SELECT name AS PoolName FROM sys.resource_governor_resource_pools WHERE name = N'$Name'") | Where-Object { $PSItem.PoolName })
            return $rows.Count -gt 0
        }

        # MAX_CPU_PERCENT is what tells "left alone" apart from "dropped and recreated from the
        # source". A name check alone passes either way.
        function Get-TestResourcePoolMaxCpu {
            param(
                $Server,
                $Name
            )
            return @($Server.Query("SELECT max_cpu_percent AS MaxCpu FROM sys.resource_governor_resource_pools WHERE name = N'$Name'")).MaxCpu
        }

        function Get-TestResourcePoolGroupCount {
            param(
                $Server,
                $Name
            )
            $query = "SELECT g.name AS GroupName FROM sys.resource_governor_workload_groups g JOIN sys.resource_governor_resource_pools p ON g.pool_id = p.pool_id WHERE p.name = N'$Name'"
            return @($Server.Query($query) | Where-Object { $PSItem.GroupName }).Count
        }

        $splatQuery = @{
            SqlInstance   = $TestConfig.InstanceCopy1
            WarningAction = "SilentlyContinue"
        }

        # Create prod pool and workload
        Invoke-DbaQuery @splatQuery -Query "CREATE RESOURCE POOL dbatoolsci_prod WITH (MAX_CPU_PERCENT = 100, MIN_CPU_PERCENT = 50)"
        Invoke-DbaQuery @splatQuery -Query "CREATE WORKLOAD GROUP dbatoolsci_prodprocessing WITH (IMPORTANCE = MEDIUM) USING dbatoolsci_prod"

        # Create offhours pool and workload
        Invoke-DbaQuery @splatQuery -Query "CREATE RESOURCE POOL dbatoolsci_offhoursprocessing WITH (MAX_CPU_PERCENT = 50, MIN_CPU_PERCENT = 0)"
        Invoke-DbaQuery @splatQuery -Query "CREATE WORKLOAD GROUP dbatoolsci_goffhoursprocessing WITH (IMPORTANCE = LOW) USING dbatoolsci_offhoursprocessing"

        Invoke-DbaQuery @splatQuery -Query "CREATE RESOURCE POOL $whatIfPool WITH (MAX_CPU_PERCENT = 40, MIN_CPU_PERCENT = 0)"
        Invoke-DbaQuery @splatQuery -Query "CREATE WORKLOAD GROUP $whatIfGroup WITH (IMPORTANCE = LOW) USING $whatIfPool"

        # Deliberately no workload group on this one.
        Invoke-DbaQuery @splatQuery -Query "CREATE RESOURCE POOL $barePool WITH (MAX_CPU_PERCENT = 45, MIN_CPU_PERCENT = 0)"

        Invoke-DbaQuery @splatQuery -Query "ALTER RESOURCE GOVERNOR RECONFIGURE"

        # Create and set classifier function
        Invoke-DbaQuery @splatQuery -Query "CREATE FUNCTION dbatoolsci_fnRG() RETURNS sysname WITH SCHEMABINDING AS BEGIN RETURN N'dbatoolsci_goffhoursprocessing' END"
        Invoke-DbaQuery @splatQuery -Query "ALTER RESOURCE GOVERNOR with (CLASSIFIER_FUNCTION = dbo.dbatoolsci_fnRG); ALTER RESOURCE GOVERNOR RECONFIGURE;"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatCleanup = @{
            SqlInstance   = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
            WarningAction = "SilentlyContinue"
        }

        Get-DbaProcess -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue

        # Cleanup all created objects.
        Invoke-DbaQuery @splatCleanup -Query "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL); ALTER RESOURCE GOVERNOR RECONFIGURE"
        Invoke-DbaQuery @splatCleanup -Query "DROP FUNCTION [dbo].[dbatoolsci_fnRG];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue
        Invoke-DbaQuery @splatCleanup -Query "DROP WORKLOAD GROUP [dbatoolsci_prodprocessing];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue
        Invoke-DbaQuery @splatCleanup -Query "DROP WORKLOAD GROUP [dbatoolsci_goffhoursprocessing];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue
        Invoke-DbaQuery @splatCleanup -Query "DROP WORKLOAD GROUP [$whatIfGroup];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue
        Invoke-DbaQuery @splatCleanup -Query "DROP RESOURCE POOL [dbatoolsci_offhoursprocessing];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue
        Invoke-DbaQuery @splatCleanup -Query "DROP RESOURCE POOL [dbatoolsci_prod];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue
        Invoke-DbaQuery @splatCleanup -Query "DROP RESOURCE POOL [$whatIfPool];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue
        Invoke-DbaQuery @splatCleanup -Query "DROP RESOURCE POOL [$barePool];ALTER RESOURCE GOVERNOR RECONFIGURE" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When the pool does not exist on the destination" {
        BeforeEach {
            Remove-TestResourcePool -Server $destServer -Name $whatIfPool
        }

        It "Does not create the pool on the destination when -WhatIf is used" {
            Test-TestResourcePoolExists -Server $destServer -Name $whatIfPool | Should -BeFalse

            $splatWhatIf = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ResourcePool  = $whatIfPool
                WarningAction = "SilentlyContinue"
                WhatIf        = $true
            }
            { Copy-DbaResourceGovernor @splatWhatIf } | Should -Not -Throw

            Test-TestResourcePoolExists -Server $destServer -Name $whatIfPool | Should -BeFalse
        }

        It "Emits no result object under -WhatIf because every status is gated by ShouldProcess" {
            $splatWhatIf = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ResourcePool  = $whatIfPool
                WarningAction = "SilentlyContinue"
                WhatIf        = $true
            }
            $whatIfResult = Copy-DbaResourceGovernor @splatWhatIf
            $whatIfResult | Should -BeNullOrEmpty
        }

        It "Should create the pool on the destination and report it Successful" {
            # The positive control for both -WhatIf legs above: without it they would pass just as
            # well against a command that copies nothing at all.
            $splatCopyPool = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ResourcePool  = $whatIfPool
                WarningAction = "SilentlyContinue"
            }
            $statuses = @(Copy-DbaResourceGovernor @splatCopyPool)

            $poolStatus = $statuses | Where-Object { $PSItem.Type -eq "Resource Governor Pool" -and $PSItem.Name -eq $whatIfPool }
            $poolStatus | Should -Not -BeNullOrEmpty
            $poolStatus.Status | Should -Be "Successful"
            $poolStatus.SourceServer | Should -Be $sourceServer.Name
            $poolStatus.DestinationServer | Should -Be $destServer.Name
            $poolStatus.PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"

            $groupStatus = $statuses | Where-Object { $PSItem.Type -eq "Resource Governor Pool Workgroup" -and $PSItem.Name -eq $whatIfGroup }
            $groupStatus.Status | Should -Be "Successful"

            Test-TestResourcePoolExists -Server $destServer -Name $whatIfPool | Should -BeTrue
            # The settings travelled, not just the name.
            Get-TestResourcePoolMaxCpu -Server $destServer -Name $whatIfPool | Should -Be 40
        }
    }

    Context "When copying resource governor settings" {
        BeforeAll {
            # The context above leaves $whatIfPool on the destination. This leg copies the whole
            # configuration with -Force, which would then take the drop-and-recreate path for that
            # one pool - a path that fails on any pool with a workload group (see the -Force
            # context below). Clearing it keeps this leg measuring the whole-configuration copy
            # instead of silently becoming a second, worse test of -Force.
            Remove-TestResourcePool -Server $destServer -Name $whatIfPool
        }

        It "Copies the resource governor successfully" {
            $splatCopyRG = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                Force         = $true
                WarningAction = "SilentlyContinue"
            }

            $results = Copy-DbaResourceGovernor @splatCopyRG
            $results.Status | Select-Object -Unique | Should -BeExactly "Successful"
            $results.Status.Count | Should -BeGreaterThan 3
            $results.Name | Should -Contain "dbatoolsci_prod"
        }

        It "Returns the proper classifier function" {
            $results = Get-DbaRgClassifierFunction -SqlInstance $TestConfig.InstanceCopy2
            $results.Name | Should -BeExactly "dbatoolsci_fnRG"
        }
    }

    Context "When the pool already exists on the destination" {
        BeforeEach {
            # Divergent on purpose. The skip leg and the -Force legs are told apart by which
            # MAX_CPU_PERCENT is on the destination afterwards, and every one of them passes a
            # name check. The marker has to sit above the pool's own MIN_CPU_PERCENT of 50 or SQL
            # Server rejects the ALTER outright and the leg dies in setup instead of measuring.
            $destServer.Query("ALTER RESOURCE POOL [$prodPool] WITH (MAX_CPU_PERCENT = 77)")
            $destServer.Query("ALTER RESOURCE GOVERNOR RECONFIGURE")
        }

        It "Should report it Skipped and leave the destination settings untouched" {
            Get-TestResourcePoolMaxCpu -Server $destServer -Name $prodPool | Should -Be 77

            $splatCopyExisting = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ResourcePool  = $prodPool
                WarningAction = "SilentlyContinue"
            }
            $statuses = @(Copy-DbaResourceGovernor @splatCopyExisting)

            $poolStatus = $statuses | Where-Object { $PSItem.Type -eq "Resource Governor Pool" -and $PSItem.Name -eq $prodPool }
            $poolStatus | Should -Not -BeNullOrEmpty
            $poolStatus.Status | Should -Be "Skipped"
            $poolStatus.Notes | Should -Be "Already exists on destination"

            Get-TestResourcePoolMaxCpu -Server $destServer -Name $prodPool | Should -Be 77
        }

        # The two legs below are a matched pair, and they must stay one. The first records
        # behaviour nobody wants; the second is what tells that apart from "-Force never works",
        # which is the reading a lone failing leg invites.
        It "Should fail and destroy the workload groups when -Force hits a pool that has them" {
            # Characterization, not an endorsement. Dropping a workload group removes it from the
            # live SMO collection the command is enumerating, so the enumerator throws before the
            # pool itself is dropped: the destination keeps the settings the caller asked to
            # replace AND loses its workload groups. Registered upstream; the port carries it
            # verbatim, so this leg is what proves the flip did not change it.
            Get-TestResourcePoolMaxCpu -Server $destServer -Name $prodPool | Should -Be 77
            Get-TestResourcePoolGroupCount -Server $destServer -Name $prodPool | Should -BeGreaterThan 0

            $splatCopyForce = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ResourcePool  = $prodPool
                Force         = $true
                WarningAction = "SilentlyContinue"
            }
            $statuses = @(Copy-DbaResourceGovernor @splatCopyForce)

            $poolStatus = $statuses | Where-Object { $PSItem.Type -eq "Resource Governor Pool" -and $PSItem.Name -eq $prodPool }
            $poolStatus | Should -Not -BeNullOrEmpty
            $poolStatus.Status | Should -Be "Failed"
            $poolStatus.Notes | Should -BeLike "*Collection was modified*"

            # The recreate never ran, so the source's 100 did not land.
            Get-TestResourcePoolMaxCpu -Server $destServer -Name $prodPool | Should -Be 77
            # But the first Drop() had already committed.
            Get-TestResourcePoolGroupCount -Server $destServer -Name $prodPool | Should -Be 0
        }

        It "Should drop and recreate the pool when -Force hits one with no workload groups" {
            $destServer.Query("ALTER RESOURCE POOL [$barePool] WITH (MAX_CPU_PERCENT = 78)")
            $destServer.Query("ALTER RESOURCE GOVERNOR RECONFIGURE")
            Get-TestResourcePoolMaxCpu -Server $destServer -Name $barePool | Should -Be 78
            Get-TestResourcePoolGroupCount -Server $destServer -Name $barePool | Should -Be 0

            $splatCopyForceBare = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                ResourcePool  = $barePool
                Force         = $true
                WarningAction = "SilentlyContinue"
            }
            $statuses = @(Copy-DbaResourceGovernor @splatCopyForceBare)

            $poolStatus = $statuses | Where-Object { $PSItem.Type -eq "Resource Governor Pool" -and $PSItem.Name -eq $barePool }
            $poolStatus | Should -Not -BeNullOrEmpty
            $poolStatus.Status | Should -Be "Successful"

            # The empty foreach never touches the collection, so the drop and recreate both run
            # and the source's setting lands.
            Get-TestResourcePoolMaxCpu -Server $destServer -Name $barePool | Should -Be 45
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
            # succeeds silently on a path that already exists and leaves its permissions
            # alone, so the one thing that must not happen is adopting somebody else's
            # directory and executing a script out of it.
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
`$resolved = Get-Command -Name Copy-DbaResourceGovernor -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaResourceGovernor"
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
