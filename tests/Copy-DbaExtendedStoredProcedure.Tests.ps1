#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaExtendedStoredProcedure",
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
                "ExtendedProcedure",
                "ExcludeExtendedProcedure",
                "DestinationPath",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Fixtures are created with sp_addextendedproc rather than with this command, because the
    # command cannot create one: sys.sql_modules never carries a row for a type='X' object, so the
    # DllPath column is always DBNull. DBNull is truthy in both editions, so the sp_helpextendedproc
    # fallback below it never runs and Split-Path is handed the DBNull. The same truthiness kills
    # the -Force drop branch one line before its DROP. Neither mutating path is reachable, which is
    # why every leg that would change a destination asserts Failed instead. That is the shipping
    # behaviour, pinned deliberately; changing it is a source fix, not a port decision.

    Context "When the procedure does not exist on the destination" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $createName = "xp_dbatoolsci_create"

            $splatCreateSource = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = "master"
                Query       = "EXEC dbo.sp_addextendedproc @functname = N'$createName', @dllname = N'dbatoolsci.dll'"
            }
            $null = Invoke-DbaQuery @splatCreateSource

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            foreach ($cleanupInstance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
                $splatCleanupCreate = @{
                    SqlInstance = $cleanupInstance
                    Database    = "master"
                    Query       = "IF EXISTS (SELECT 1 FROM sys.procedures WHERE type = 'X' AND is_ms_shipped = 0 AND name = '$createName') EXEC dbo.sp_dropextendedproc @functname = N'dbo.$createName'"
                }
                $null = Invoke-DbaQuery @splatCleanupCreate
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should report the procedure it processed and land nothing on the destination" {
            $splatCopy = @{
                Source            = $TestConfig.InstanceCopy1
                Destination       = $TestConfig.InstanceCopy2
                ExtendedProcedure = $createName
                WarningAction     = "SilentlyContinue"
            }
            $results = Copy-DbaExtendedStoredProcedure @splatCopy
            @($results).Count | Should -Be 1
            $results.Name | Should -Be $createName
            $results.Schema | Should -Be "dbo"
            $results.Type | Should -Be "Extended Stored Procedure"
            $results.SourceServer | Should -Be $TestConfig.InstanceCopy1
            $results.DestinationServer | Should -Be $TestConfig.InstanceCopy2
            $results.Status | Should -Be "Failed"

            $splatCreateCheck = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "master"
                Query       = "SELECT name FROM sys.procedures WHERE type = 'X' AND is_ms_shipped = 0 AND name = '$createName'"
            }
            Invoke-DbaQuery @splatCreateCheck | Should -BeNullOrEmpty
        }
    }

    Context "When only some procedures are wanted" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $filterKeepName = "xp_dbatoolsci_filterkeep"
            $filterSkipName = "xp_dbatoolsci_filterskip"

            foreach ($fixtureName in $filterKeepName, $filterSkipName) {
                $splatCreateFilter = @{
                    SqlInstance = $TestConfig.InstanceCopy1
                    Database    = "master"
                    Query       = "EXEC dbo.sp_addextendedproc @functname = N'$fixtureName', @dllname = N'dbatoolsci.dll'"
                }
                $null = Invoke-DbaQuery @splatCreateFilter
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            foreach ($cleanupInstance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
                foreach ($fixtureName in $filterKeepName, $filterSkipName) {
                    $splatCleanupFilter = @{
                        SqlInstance = $cleanupInstance
                        Database    = "master"
                        Query       = "IF EXISTS (SELECT 1 FROM sys.procedures WHERE type = 'X' AND is_ms_shipped = 0 AND name = '$fixtureName') EXEC dbo.sp_dropextendedproc @functname = N'dbo.$fixtureName'"
                    }
                    $null = Invoke-DbaQuery @splatCleanupFilter
                }
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should process only the named procedure when -ExtendedProcedure is used" {
            # Both fixtures sit on the source, so a port that ignored the include filter would
            # return two results here instead of one.
            $splatInclude = @{
                Source            = $TestConfig.InstanceCopy1
                Destination       = $TestConfig.InstanceCopy2
                ExtendedProcedure = $filterKeepName
                WarningAction     = "SilentlyContinue"
            }
            $results = Copy-DbaExtendedStoredProcedure @splatInclude
            @($results).Count | Should -Be 1
            $results.Name | Should -Be $filterKeepName
        }

        It "Should leave out the named procedure when -ExcludeExtendedProcedure is used" {
            $splatExclude = @{
                Source                   = $TestConfig.InstanceCopy1
                Destination              = $TestConfig.InstanceCopy2
                ExcludeExtendedProcedure = $filterSkipName
                WarningAction            = "SilentlyContinue"
            }
            $results = Copy-DbaExtendedStoredProcedure @splatExclude
            @($results).Name | Should -Contain $filterKeepName
            @($results).Name | Should -Not -Contain $filterSkipName
        }
    }

    Context "When the procedure already exists on the destination" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $existingName = "xp_dbatoolsci_existing"

            # Seeded on both sides directly. The command itself cannot seed the destination - see
            # the note at the top of this Describe.
            foreach ($seedInstance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
                $splatSeedExisting = @{
                    SqlInstance = $seedInstance
                    Database    = "master"
                    Query       = "EXEC dbo.sp_addextendedproc @functname = N'$existingName', @dllname = N'dbatoolsci.dll'"
                }
                $null = Invoke-DbaQuery @splatSeedExisting
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            foreach ($cleanupInstance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
                $splatCleanupExisting = @{
                    SqlInstance = $cleanupInstance
                    Database    = "master"
                    Query       = "IF EXISTS (SELECT 1 FROM sys.procedures WHERE type = 'X' AND is_ms_shipped = 0 AND name = '$existingName') EXEC dbo.sp_dropextendedproc @functname = N'dbo.$existingName'"
                }
                $null = Invoke-DbaQuery @splatCleanupExisting
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should report Skipped and leave the destination procedure alone" {
            $splatSkip = @{
                Source            = $TestConfig.InstanceCopy1
                Destination       = $TestConfig.InstanceCopy2
                ExtendedProcedure = $existingName
                WarningAction     = "SilentlyContinue"
            }
            $results = Copy-DbaExtendedStoredProcedure @splatSkip
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "Already exists on destination"

            $splatSkipCheck = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "master"
                Query       = "SELECT name FROM sys.procedures WHERE type = 'X' AND is_ms_shipped = 0 AND name = '$existingName'"
            }
            (Invoke-DbaQuery @splatSkipCheck).name | Should -Be $existingName
        }

        It "Should reach no ShouldProcess branch at all when -WhatIf is used with -Force" {
            # -WhatIf turns both ShouldProcess calls false, so nothing is emitted - and the leg
            # below, the same call without -WhatIf, is the positive control that separates that
            # from a command which simply returns nothing. The destination check is here for
            # completeness rather than as the discriminator: the drop this command would attempt is
            # unreachable in any case, for the DllPath reason the leg below records.
            $splatWhatIf = @{
                Source            = $TestConfig.InstanceCopy1
                Destination       = $TestConfig.InstanceCopy2
                ExtendedProcedure = $existingName
                Force             = $true
                WhatIf            = $true
                WarningAction     = "SilentlyContinue"
            }
            $results = Copy-DbaExtendedStoredProcedure @splatWhatIf
            $results | Should -BeNullOrEmpty

            $splatWhatIfCheck = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "master"
                Query       = "SELECT name FROM sys.procedures WHERE type = 'X' AND is_ms_shipped = 0 AND name = '$existingName'"
            }
            (Invoke-DbaQuery @splatWhatIfCheck).name | Should -Be $existingName
        }

        It "Should take the drop branch rather than the skip branch when -Force is used" {
            # -Force routes to the drop branch, and dies there one line ahead of the drop itself:
            # $dropXP.DllPath is DBNull, DBNull is truthy, so Split-Path throws before
            # sp_dropextendedproc is ever assembled. The destination procedure therefore survives -
            # the status and the notes are what separate this branch from the Skipped one above,
            # and a port that ignored -Force would answer "Skipped" here.
            $splatForce = @{
                Source            = $TestConfig.InstanceCopy1
                Destination       = $TestConfig.InstanceCopy2
                ExtendedProcedure = $existingName
                Force             = $true
                WarningAction     = "SilentlyContinue"
            }
            $results = Copy-DbaExtendedStoredProcedure @splatForce
            $results.Status | Should -Be "Failed"
            $results.Notes | Should -BeLike "*Cannot bind argument to parameter*"

            $splatForceCheck = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "master"
                Query       = "SELECT name FROM sys.procedures WHERE type = 'X' AND is_ms_shipped = 0 AND name = '$existingName'"
            }
            (Invoke-DbaQuery @splatForceCheck).name | Should -Be $existingName
        }
    }

    Context "When one call spans more than one destination" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $multiName = "xp_dbatoolsci_multi"

            $splatSeedMulti = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = "master"
                Query       = "EXEC dbo.sp_addextendedproc @functname = N'$multiName', @dllname = N'dbatoolsci.dll'"
            }
            $null = Invoke-DbaQuery @splatSeedMulti

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            foreach ($cleanupInstance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
                $splatCleanupMulti = @{
                    SqlInstance = $cleanupInstance
                    Database    = "master"
                    Query       = "IF EXISTS (SELECT 1 FROM sys.procedures WHERE type = 'X' AND is_ms_shipped = 0 AND name = '$multiName') EXEC dbo.sp_dropextendedproc @functname = N'dbo.$multiName'"
                }
                $null = Invoke-DbaQuery @splatCleanupMulti
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should emit one result per destination, each with its own status" {
            # The source instance is deliberately one of the destinations: the procedure is already
            # there, so the two results must differ in status as well as in server. A port that
            # handled only the first destination would return one object and still look green
            # against a Count-free assertion.
            $splatBoth = @{
                Source            = $TestConfig.InstanceCopy1
                Destination       = $TestConfig.InstanceCopy2, $TestConfig.InstanceCopy1
                ExtendedProcedure = $multiName
                WarningAction     = "SilentlyContinue"
            }
            $results = Copy-DbaExtendedStoredProcedure @splatBoth
            @($results).Count | Should -Be 2
            @($results.DestinationServer | Sort-Object -Unique).Count | Should -Be 2
            ($results | Where-Object DestinationServer -eq $TestConfig.InstanceCopy2).Status | Should -Be "Failed"
            ($results | Where-Object DestinationServer -eq $TestConfig.InstanceCopy1).Status | Should -Be "Skipped"
        }
    }

    Context "When a server cannot be reached" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $unreachableName = "xp_dbatoolsci_unreachable"

            $splatSeedUnreachable = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = "master"
                Query       = "EXEC dbo.sp_addextendedproc @functname = N'$unreachableName', @dllname = N'dbatoolsci.dll'"
            }
            $null = Invoke-DbaQuery @splatSeedUnreachable

            $previousConnectTimeout = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value 1

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Set-DbatoolsConfig -FullName sql.connection.timeout -Value $previousConnectTimeout
            foreach ($cleanupInstance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
                $splatCleanupUnreachable = @{
                    SqlInstance = $cleanupInstance
                    Database    = "master"
                    Query       = "IF EXISTS (SELECT 1 FROM sys.procedures WHERE type = 'X' AND is_ms_shipped = 0 AND name = '$unreachableName') EXEC dbo.sp_dropextendedproc @functname = N'dbo.$unreachableName'"
                }
                $null = Invoke-DbaQuery @splatCleanupUnreachable
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should warn on the unreachable destination and still reach the reachable one" {
            # Stop-Function -Continue binds to the destination loop, so the second destination has to
            # be reached anyway. It also proves the warning stream survives the hop: a swallowed 3>&1
            # leaves -WarningVariable empty.
            $connectWarning = $null
            $splatMixed = @{
                Source            = $TestConfig.InstanceCopy1
                Destination       = $TestConfig.InstanceUnreachable, $TestConfig.InstanceCopy2
                ExtendedProcedure = $unreachableName
                WarningVariable   = "connectWarning"
                WarningAction     = "SilentlyContinue"
                ErrorAction       = "SilentlyContinue"
            }
            $results = Copy-DbaExtendedStoredProcedure @splatMixed
            $connectWarning | Should -Not -BeNullOrEmpty
            ($results | Where-Object DestinationServer -eq $TestConfig.InstanceCopy2).Status | Should -Be "Failed"
        }

        It "Should reach no destination at all when the source cannot be connected" {
            # The source connect failure latches Test-FunctionInterrupt, and the guard ahead of the
            # destination loop is what turns that latch into "nothing happened". Without it the loop
            # would run against a null source server and produce results.
            $sourceWarning = $null
            $splatDeadSource = @{
                Source            = $TestConfig.InstanceUnreachable
                Destination       = $TestConfig.InstanceCopy2
                ExtendedProcedure = $unreachableName
                WarningVariable   = "sourceWarning"
                WarningAction     = "SilentlyContinue"
                ErrorAction       = "SilentlyContinue"
            }
            $results = Copy-DbaExtendedStoredProcedure @splatDeadSource
            $sourceWarning | Should -Not -BeNullOrEmpty
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
`$resolved = Get-Command -Name Copy-DbaExtendedStoredProcedure -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaExtendedStoredProcedure"
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
