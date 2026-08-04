#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaLogin",
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
                "Login",
                "ExcludeLogin",
                "ExcludeSystemLogins",
                "SyncSaName",
                "OutFile",
                "InputObject",
                "LoginRenameHashtable",
                "KillActiveConnection",
                "ExcludePermissionSync",
                "ExcludeDatabaseMapping",
                "NewSid",
                "ObjectLevel",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "OutFile behavior" {
        BeforeAll {
            Mock Test-FunctionInterrupt { $false } -ModuleName dbatools
            Mock Get-DbaLogin {
                [PSCustomObject]@{
                    Name = "tester"
                }
            } -ModuleName dbatools
            Mock Export-DbaLogin {
                $FilePath
            } -ModuleName dbatools
        }

        It "passes ExcludeDatabase to Export-DbaLogin when ExcludeDatabaseMapping is used" {
            $null = Copy-DbaLogin -Source "sql1" -Login "tester" -OutFile "C:\temp\logins.sql" -ExcludeDatabaseMapping

            Should -Invoke Export-DbaLogin -Times 1 -Exactly -ModuleName dbatools -ParameterFilter {
                $FilePath -eq "C:\temp\logins.sql" -and $ExcludeDatabase
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # drop all objects
        Function Initialize-TestLogin {
            Param ($Instance, $Login)
            Get-DbaProcess -SqlInstance $Instance -Login $Login | Stop-DbaProcess
            if ($l = Get-DbaLogin -SqlInstance $Instance -Login $Login) {
                foreach ($map in $l.EnumDatabaseMappings()) {
                    $null = Invoke-DbaQuery -SqlInstance $Instance -Database $map.DbName -Query "DROP USER [$($map.Username)]"
                }
                $l.Drop()
            }
            $dropUserQuery = "IF EXISTS (SELECT * FROM sys.database_principals WHERE name = '{0}') DROP USER [{0}]" -f $Login
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropUserQuery
        }
        $logins = "claudio", "port", "tester", "tester_new"
        $dropTableQuery = "IF EXISTS (SELECT * FROM sys.tables WHERE name = 'tester_table') DROP TABLE tester_table"
        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            foreach ($login in $logins) {
                Initialize-TestLogin -Instance $instance -Login $login
            }
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropTableQuery

        }

        # create objects
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -InputFile "$($TestConfig.appveyorlabrepo)\sql2008-scripts\logins.sql"

        $tableQuery = @("CREATE TABLE tester_table (a int)", "CREATE USER tester FOR LOGIN tester", "GRANT INSERT ON tester_table TO tester;")
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Query ($tableQuery -join '; ')
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb -Query $tableQuery[0]

        # we want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    BeforeEach {
        # cleanup targets
        Initialize-TestLogin -Instance $TestConfig.InstanceCopy2 -Login tester
        Initialize-TestLogin -Instance $TestConfig.InstanceCopy1 -Login tester_new
    }
    AfterAll {
        # we want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # cleanup everything
        $logins = "claudio", "port", "tester", "tester_new"

        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            foreach ($login in $logins) {
                Initialize-TestLogin -Instance $instance -Login $login
            }
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropTableQuery
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Copy login with the same properties." {
        It "Should copy successfully" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Login Tester
            $results.Status | Should -Be "Successful"
            $login1 = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -login Tester
            $login2 = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy2 -login Tester

            $login2 | Should -Not -BeNullOrEmpty

            # Compare its value
            $login1.Name | Should -Be $login2.Name
            $login1.Language | Should -Be $login2.Language
            $login1.Credential | Should -Be $login2.Credential
            $login1.DefaultDatabase | Should -Be $login2.DefaultDatabase
            $login1.IsDisabled | Should -Be $login2.IsDisabled
            $login1.IsLocked | Should -Be $login2.IsLocked
            $login1.IsPasswordExpired | Should -Be $login2.IsPasswordExpired
            $login1.PasswordExpirationEnabled | Should -Be $login2.PasswordExpirationEnabled
            $login1.PasswordPolicyEnforced | Should -Be $login2.PasswordPolicyEnforced
            $login1.Sid | Should -Be $login2.Sid
            $login1.Status | Should -Be $login2.Status
        }

        It "Should login with newly created Sql Login (also tests credential login) and gets name" {
            $password = ConvertTo-SecureString -Force -AsPlainText tester1
            $cred = New-Object System.Management.Automation.PSCredential ("tester", $password)
            $s = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -SqlCredential $cred
            $s.Name | Should -Be $TestConfig.InstanceCopy1
        }
    }

    Context "WhatIf" {
        It "Should emit nothing and leave the destination login uncreated" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Login tester -WhatIf
            @($results).Count | Should -Be 0
            # The absence of output is satisfied by a command that did nothing at all, so the
            # side effect is what actually distinguishes -WhatIf from a no-op.
            Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy2 -Login tester | Should -BeNullOrEmpty
        }
    }

    Context "Two logins through the pipeline in one call" {
        BeforeEach {
            'tester', 'port' | ForEach-Object {
                Initialize-TestLogin -Instance $TestConfig.InstanceCopy2 -Login $PSItem
            }
        }
        It "Should copy each piped login exactly once" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester, port | Copy-DbaLogin -Destination $TestConfig.InstanceCopy2
            # One status object per piped login. A second record that inherited the first
            # record's collected logins would emit three, and a second record that inherited
            # the first record's source connection would report the wrong name - the count and
            # the exact name set are what separate those from a correct per-record run.
            @($results).Count | Should -Be 2
            @($results.Name | Sort-Object) | Should -Be @("port", "tester")
            $results.Status | Should -Be @("Successful", "Successful")
            Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy2 -Login tester | Should -Not -BeNullOrEmpty
            Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy2 -Login port | Should -Not -BeNullOrEmpty
        }
    }

    Context "No overwrite" {
        It "Should say skipped" {
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -InputFile "$($TestConfig.appveyorlabrepo)\sql2008-scripts\logins.sql"
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Login tester
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "Already exists on destination"
        }
    }

    Context "ExcludeSystemLogins Parameter" {
        It "Should say skipped" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ExcludeSystemLogins
            $results.Status | Should -Contain 'Skipped'
            if (([DbaInstanceParameter]$TestConfig.InstanceCopy1).ComputerName -ne ([DbaInstanceParameter]$TestConfig.InstanceCopy2).ComputerName) {
                $results.Notes | Should -Contain 'Local machine name'
            } else {
                $results.Notes | Should -Contain 'System login'
            }
        }
    }

    Context "Supports pipe" {
        It "migrates the one tester login" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester | Copy-DbaLogin -Destination $TestConfig.InstanceCopy2 -Force
            $results.Name | Should -Be "tester"
            $results.Status | Should -Be "Successful"
        }
    }

    Context "Supports cloning" {
        It "clones the one tester login" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Login tester -Destination $TestConfig.InstanceCopy1 -Force -LoginRenameHashtable @{ tester = 'tester_new' } -NewSid
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester_new | Should -Not -BeNullOrEmpty
        }
        It "clones the one tester login using pipe" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester | Copy-DbaLogin -Destination $TestConfig.InstanceCopy1 -Force -LoginRenameHashtable @{ tester = 'tester_new' } -NewSid
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester_new | Should -Not -BeNullOrEmpty
        }
        It "clones the one tester login to a different server with a new name" {
            'tester', 'tester_new' | ForEach-Object {
                Initialize-TestLogin -Instance $TestConfig.InstanceCopy2 -Login $_
            }
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester | Copy-DbaLogin -Destination $TestConfig.InstanceCopy2 -LoginRenameHashtable @{ tester = 'tester_new' }
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $login = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2).Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $login | Remove-DbaLogin -Force
        }
    }

    Context "Supports db object permissions" {
        BeforeAll {
            $tempExportFile = [System.IO.Path]::GetTempFileName()
        }
        BeforeEach {
            'tester', 'tester_new' | ForEach-Object {
                Initialize-TestLogin -Instance $TestConfig.InstanceCopy2 -Login $_
            }
        }
        AfterAll {
            Remove-Item -Path $tempExportFile -Force
        }
        It "clones the one tester login with sysadmin permissions" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Login tester -Destination $TestConfig.InstanceCopy2 -LoginRenameHashtable @{ tester = 'tester_new' }
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $i2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $login = $i2.Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $role = $i2.Roles['sysadmin']
            $role.EnumMemberNames() | Should -Contain $results.Name
        }
        It "clones the one tester login with object permissions" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Login tester -Destination $TestConfig.InstanceCopy2 -LoginRenameHashtable @{ tester = 'tester_new' } -ObjectLevel
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $i2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $login = $i2.Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $permissions = Export-DbaUser -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb -User tester_new -Passthru
            $permissions | Should -BeLike '*GRANT INSERT ON OBJECT::`[dbo`].`[tester_table`] TO `[tester_new`]*'
        }
        It "scripts out two tester login with object permissions" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Login tester, port -OutFile $tempExportFile -ObjectLevel
            $results | Should -Be $tempExportFile
            $permissions = Get-Content $tempExportFile -Raw
            $permissions | Should -BeLike '*CREATE LOGIN `[tester`]*'
            $permissions | Should -Match "(ALTER SERVER ROLE \[sysadmin\] ADD MEMBER \[tester\]|EXEC sp_addsrvrolemember @rolename=N'sysadmin', @loginame=N'tester')"
            $permissions | Should -BeLike '*GRANT INSERT ON OBJECT::`[dbo`].`[tester_table`] TO `[tester`]*'
            $permissions | Should -BeLike '*CREATE LOGIN `[port`]*'
            $permissions | Should -BeLike '*GRANT CONNECT SQL TO `[port`]*'
        }
    }

    Context "Regression test for issue #9163 - Warn when login not found" {
        It "Should warn when specified login does not exist on source" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = "nonexistentlogin"
            }
            $result = Copy-DbaLogin @splatCopy -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warn | Should -Not -BeNullOrEmpty
            $warn | Should -BeLike "*nonexistentlogin*not found*"
        }

        It "Should warn for each non-existent login when multiple are specified" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = "nonexistent1", "nonexistent2"
            }
            $result = Copy-DbaLogin @splatCopy -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 2
            $warn[0] | Should -BeLike "*nonexistent1*not found*"
            $warn[1] | Should -BeLike "*nonexistent2*not found*"
        }

        It "Should not warn when login exists" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = "tester"
            }
            $result = Copy-DbaLogin @splatCopy -WarningVariable warn -WarningAction SilentlyContinue
            $result.Status | Should -Be "Successful"
            $warn | Should -BeNullOrEmpty
        }
    }

    Context "Regression test for issue #8572 - Windows group lockout protection" {
        It "Should not throw when processing SQL logins with -Force" {
            # Verify SQL logins are not affected by Windows group checks
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = "tester"
                Force       = $true
            }
            $results = Copy-DbaLogin @splatCopy
            $results.Status | Should -Be "Successful"
        }

        It "Should handle Windows logins gracefully when not in a domain" {
            # This test verifies the code path doesn't break non-domain scenarios
            # In CI (non-domain), Windows logins typically fail earlier in the process
            # but the lockout protection code should not introduce new errors
            {
                $splatCopy = @{
                    Source      = $TestConfig.InstanceCopy1
                    Destination = $TestConfig.InstanceCopy2
                    Login       = "NT AUTHORITY\SYSTEM"
                    Force       = $true
                }
                Copy-DbaLogin @splatCopy -WarningAction SilentlyContinue
            } | Should -Not -Throw
        }

        # The high-privilege branch itself - the group that owns sysadmin, securityadmin or
        # ALTER ANY LOGIN and that the caller reaches the instance THROUGH - has no automated
        # coverage here. Reproducing it needs a domain, an AD group holding one of those
        # privileges, and a test principal with no direct login of its own; this lab is not
        # domain-joined for the copy pair, so the only leg that could be written against it
        # would assert on the text of the implementation rather than on its behaviour.
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
`$resolved = Get-Command -Name Copy-DbaLogin -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaLogin"
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
