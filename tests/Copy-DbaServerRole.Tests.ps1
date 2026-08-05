#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaServerRole",
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
                "ServerRole",
                "ExcludeServerRole",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testRoleName = "dbatoolsci_ServerRole_$(Get-Random)"
        $sourceServerConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $sourceServerConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$testRoleName' AND type = 'R') DROP SERVER ROLE [$testRoleName]")
        $sourceServerConn.Query("CREATE SERVER ROLE [$testRoleName]")
        $sourceServerConn.Query("GRANT CONNECT ANY DATABASE TO [$testRoleName]")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $serversToCleanup = @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)
        foreach ($serverInstance in $serversToCleanup) {
            $cleanupServerConn = Connect-DbaInstance -SqlInstance $serverInstance
            $cleanupServerConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$testRoleName' AND type = 'R') DROP SERVER ROLE [$testRoleName]") | Out-Null
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying server roles" {
        BeforeEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $destServerConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $destServerConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$testRoleName' AND type = 'R') DROP SERVER ROLE [$testRoleName]")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should successfully copy custom server roles" {
            $splatCopyRole = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $testRoleName
            }
            $copyResults = Copy-DbaServerRole @splatCopyRole
            $copyResults.Name | Should -Be $testRoleName
            $copyResults.Status | Should -Be "Successful"
        }

        It "Should skip existing server roles" {
            $splatFirstCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $testRoleName
            }
            Copy-DbaServerRole @splatFirstCopy

            $splatSecondCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $testRoleName
            }
            $skipResults = Copy-DbaServerRole @splatSecondCopy
            $skipResults.Name | Should -Be $testRoleName
            $skipResults.Status | Should -Be "Skipped"
        }

        It "Should verify server role exists on destination" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $testRoleName
            }
            Copy-DbaServerRole @splatCopy

            $splatGetRole = @{
                SqlInstance = $TestConfig.InstanceCopy2
                ServerRole  = $testRoleName
            }
            $roleResults = Get-DbaServerRole @splatGetRole
            $roleResults.Name | Should -Contain $testRoleName
        }
    }

    Context "When the role carries permissions and members" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $permRoleName        = "dbatoolsci_PermRole_$(Get-Random)"
            $sharedLoginName     = "dbatoolsci_shared_$(Get-Random)"
            $sourceOnlyLoginName = "dbatoolsci_srconly_$(Get-Random)"

            $permSourceConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $permDestConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

            $permSourceConn.Query("CREATE LOGIN [$sharedLoginName] WITH PASSWORD = N'dbatools.IO1', CHECK_POLICY = OFF")
            $permSourceConn.Query("CREATE LOGIN [$sourceOnlyLoginName] WITH PASSWORD = N'dbatools.IO1', CHECK_POLICY = OFF")
            # Only the shared login exists on the destination - the other one is what makes the
            # "login is missing at the destination" branch reachable.
            $permDestConn.Query("CREATE LOGIN [$sharedLoginName] WITH PASSWORD = N'dbatools.IO1', CHECK_POLICY = OFF")

            $permSourceConn.Query("CREATE SERVER ROLE [$permRoleName]")
            $permSourceConn.Query("GRANT VIEW ANY DEFINITION TO [$permRoleName]")
            $permSourceConn.Query("ALTER SERVER ROLE [$permRoleName] ADD MEMBER [$sharedLoginName]")
            $permSourceConn.Query("ALTER SERVER ROLE [$permRoleName] ADD MEMBER [$sourceOnlyLoginName]")

            $splatCopyPermRole = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $permRoleName
            }
            $permCopyResults = Copy-DbaServerRole @splatCopyPermRole

            $permQuery = "SELECT p.permission_name AS PermissionName FROM sys.server_permissions AS p INNER JOIN sys.server_principals AS r ON p.grantee_principal_id = r.principal_id WHERE r.name = N'$permRoleName'"
            $destPermissions = $permDestConn.Query($permQuery)

            $memberQuery = "SELECT m.name AS MemberName FROM sys.server_role_members AS rm INNER JOIN sys.server_principals AS r ON rm.role_principal_id = r.principal_id INNER JOIN sys.server_principals AS m ON rm.member_principal_id = m.principal_id WHERE r.name = N'$permRoleName'"
            $destMembers = $permDestConn.Query($memberQuery)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $permCleanupTargets = @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)
            foreach ($permCleanupInstance in $permCleanupTargets) {
                $permCleanupConn = Connect-DbaInstance -SqlInstance $permCleanupInstance
                # Members go first: T-SQL DROP SERVER ROLE refuses a role that still has any, which
                # is not the same rule SMO's Drop() follows.
                $permCleanupConn.Query("IF EXISTS (SELECT 1 FROM sys.server_role_members AS rm INNER JOIN sys.server_principals AS r ON rm.role_principal_id = r.principal_id INNER JOIN sys.server_principals AS m ON rm.member_principal_id = m.principal_id WHERE r.name = N'$permRoleName' AND m.name = N'$sharedLoginName') ALTER SERVER ROLE [$permRoleName] DROP MEMBER [$sharedLoginName]") | Out-Null
                $permCleanupConn.Query("IF EXISTS (SELECT 1 FROM sys.server_role_members AS rm INNER JOIN sys.server_principals AS r ON rm.role_principal_id = r.principal_id INNER JOIN sys.server_principals AS m ON rm.member_principal_id = m.principal_id WHERE r.name = N'$permRoleName' AND m.name = N'$sourceOnlyLoginName') ALTER SERVER ROLE [$permRoleName] DROP MEMBER [$sourceOnlyLoginName]") | Out-Null
                $permCleanupConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$permRoleName' AND type = 'R') DROP SERVER ROLE [$permRoleName]") | Out-Null
                $permCleanupConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$sharedLoginName') DROP LOGIN [$sharedLoginName]") | Out-Null
                $permCleanupConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$sourceOnlyLoginName') DROP LOGIN [$sourceOnlyLoginName]") | Out-Null
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should report the copy as successful" {
            $permCopyResults.Name | Should -Be $permRoleName
            $permCopyResults.Status | Should -Be "Successful"
        }

        It "Should reapply the server-level permissions on the destination" {
            $destPermissions.PermissionName | Should -Contain "VIEW ANY DEFINITION"
        }

        It "Should add the members whose logins exist on the destination" {
            $destMembers.MemberName | Should -Contain $sharedLoginName
        }

        It "Should leave out members whose logins are missing from the destination" {
            $destMembers.MemberName | Should -Not -Contain $sourceOnlyLoginName
        }
    }

    Context "When the destination role is replaced with -Force" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $forceRoleName = "dbatoolsci_ForceRole_$(Get-Random)"

            $forceSourceConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $forceDestConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

            $forceSourceConn.Query("CREATE SERVER ROLE [$forceRoleName]")
            $forceSourceConn.Query("GRANT VIEW ANY DEFINITION TO [$forceRoleName]")

            $splatFirstForceCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $forceRoleName
            }
            $null = Copy-DbaServerRole @splatFirstForceCopy

            # The grant lands on the source only after the first copy, so the destination can only
            # hold it if -Force really dropped and rebuilt the role rather than skipping it.
            $forceSourceConn.Query("GRANT ALTER ANY LOGIN TO [$forceRoleName]")

            $splatForcedCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $forceRoleName
                Force       = $true
            }
            $forceCopyResults = Copy-DbaServerRole @splatForcedCopy

            $forcePermQuery = "SELECT p.permission_name AS PermissionName FROM sys.server_permissions AS p INNER JOIN sys.server_principals AS r ON p.grantee_principal_id = r.principal_id WHERE r.name = N'$forceRoleName'"
            $forceDestPermissions = $forceDestConn.Query($forcePermQuery)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $forceCleanupTargets = @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)
            foreach ($forceCleanupInstance in $forceCleanupTargets) {
                $forceCleanupConn = Connect-DbaInstance -SqlInstance $forceCleanupInstance
                $forceCleanupConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$forceRoleName' AND type = 'R') DROP SERVER ROLE [$forceRoleName]") | Out-Null
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should report the forced copy as successful" {
            $forceCopyResults.Name | Should -Be $forceRoleName
            $forceCopyResults.Status | Should -Be "Successful"
        }

        It "Should reapply the permission the source gained after the first copy" {
            $forceDestPermissions.PermissionName | Should -Contain "ALTER ANY LOGIN"
        }
    }

    Context "When run with -WhatIf" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $whatIfRoleName = "dbatoolsci_WhatIfRole_$(Get-Random)"

            $whatIfSourceConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $whatIfDestConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

            $whatIfSourceConn.Query("CREATE SERVER ROLE [$whatIfRoleName]")
            $whatIfDestConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$whatIfRoleName' AND type = 'R') DROP SERVER ROLE [$whatIfRoleName]")

            $splatWhatIfCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $whatIfRoleName
                WhatIf      = $true
            }
            $whatIfResults = Copy-DbaServerRole @splatWhatIfCopy

            $whatIfExistsQuery = "SELECT COUNT(*) AS RoleCount FROM sys.server_principals WHERE name = N'$whatIfRoleName' AND type = 'R'"
            $whatIfDestRoleCount = $whatIfDestConn.Query($whatIfExistsQuery).RoleCount

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $whatIfCleanupTargets = @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)
            foreach ($whatIfCleanupInstance in $whatIfCleanupTargets) {
                $whatIfCleanupConn = Connect-DbaInstance -SqlInstance $whatIfCleanupInstance
                $whatIfCleanupConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$whatIfRoleName' AND type = 'R') DROP SERVER ROLE [$whatIfRoleName]") | Out-Null
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should not create the role on the destination" {
            $whatIfDestRoleCount | Should -Be 0
        }

        It "Should not emit a result object" {
            # Every emit sits inside a ShouldProcess block, so -WhatIf suppresses the status object
            # along with the work it describes.
            @($whatIfResults).Count | Should -Be 0
        }
    }

    Context "When filtering which roles are copied" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $filterRoleOneName = "dbatoolsci_FilterRoleA_$(Get-Random)"
            $filterRoleTwoName = "dbatoolsci_FilterRoleB_$(Get-Random)"

            $filterSourceConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $filterSourceConn.Query("CREATE SERVER ROLE [$filterRoleOneName]")
            $filterSourceConn.Query("CREATE SERVER ROLE [$filterRoleTwoName]")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        BeforeEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $filterDestConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            foreach ($filterRoleName in @($filterRoleOneName, $filterRoleTwoName)) {
                $filterDestConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$filterRoleName' AND type = 'R') DROP SERVER ROLE [$filterRoleName]")
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $filterCleanupTargets = @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)
            foreach ($filterCleanupInstance in $filterCleanupTargets) {
                $filterCleanupConn = Connect-DbaInstance -SqlInstance $filterCleanupInstance
                foreach ($filterRoleName in @($filterRoleOneName, $filterRoleTwoName)) {
                    $filterCleanupConn.Query("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$filterRoleName' AND type = 'R') DROP SERVER ROLE [$filterRoleName]") | Out-Null
                }
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should copy every role named in a single call" {
            $splatCopyBothRoles = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                ServerRole  = $filterRoleOneName, $filterRoleTwoName
            }
            $multiCopyResults = @(Copy-DbaServerRole @splatCopyBothRoles)
            $multiCopyRecords = @($multiCopyResults | Where-Object { $null -ne $PSItem })

            $multiCopyRecords.Count | Should -Be 2
            $multiCopyRecords.Name | Should -Contain $filterRoleOneName
            $multiCopyRecords.Name | Should -Contain $filterRoleTwoName
            @($multiCopyRecords | Where-Object Status -eq "Successful").Count | Should -Be 2

            # Preserved behaviour, deliberately pinned rather than filtered out of sight: the
            # create branch calls $destServer.Query($sql) without assigning it, and that method
            # returns null for a statement with no result set, so one null reaches the pipeline
            # ahead of every role it creates. Two roles created, two nulls, four items out. The
            # skip branch runs no query and emits none, which is why the second call in this
            # Context returns a clean count. Without this assertion the filter above reads as a
            # tidy-up and a later change in what the command emits would slip past.
            $multiCopyResults.Count | Should -Be 4
        }

        It "Should skip the roles named in -ExcludeServerRole" {
            $splatCopyExcluded = @{
                Source            = $TestConfig.InstanceCopy1
                Destination       = $TestConfig.InstanceCopy2
                ServerRole        = $filterRoleOneName, $filterRoleTwoName
                ExcludeServerRole = $filterRoleTwoName
            }
            $excludeCopyResults = @(Copy-DbaServerRole @splatCopyExcluded)
            $excludeCopyRecords = @($excludeCopyResults | Where-Object { $null -ne $PSItem })

            $excludeCopyRecords.Count | Should -Be 1
            $excludeCopyRecords.Name | Should -Be $filterRoleOneName
            # One role created, so one of the stray nulls described above rides along.
            $excludeCopyResults.Count | Should -Be 2

            $excludeCheckConn = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $excludeCheckQuery = "SELECT COUNT(*) AS RoleCount FROM sys.server_principals WHERE name = N'$filterRoleTwoName' AND type = 'R'"
            $excludeCheckConn.Query($excludeCheckQuery).RoleCount | Should -Be 0
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

`$resolved = Get-Command -Name Copy-DbaServerRole -ErrorAction SilentlyContinue

`$splatResolveAll = @{

    Name        = "Copy-DbaServerRole"

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
