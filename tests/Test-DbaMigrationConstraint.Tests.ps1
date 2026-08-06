#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaMigrationConstraint",
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
                "Database",
                "ExcludeDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should take Source from the pipeline and nothing else" {
            $commandParameters = (Get-Command $CommandName).Parameters
            $commandParameters["Source"].Attributes.Where{ $PSItem -is [System.Management.Automation.ParameterAttribute] }.ValueFromPipeline | Should -Contain $true
            foreach ($otherName in "Destination", "Database", "ExcludeDatabase") {
                $commandParameters[$otherName].Attributes.Where{ $PSItem -is [System.Management.Automation.ParameterAttribute] }.ValueFromPipeline | Should -Not -Contain $true
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.InstanceCopy1 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue

        $db1 = "dbatoolsci_testMigrationConstraint"
        $db2 = "dbatoolsci_testMigrationConstraint_2"
        # The pair the carrier leg reads. sharedDb exists on both instances, so a second piped
        # record can produce a row for it at all; destOnlyDb exists only on the second, so its
        # ABSENCE from that record's rows is what shows the record never enumerated its own
        # server. One without the other proves nothing: shared alone cannot tell a carried list
        # from a re-resolved one, and dest-only alone cannot tell a carried list from a record
        # that produced nothing.
        $sharedDb = "dbatoolsci_w6028_both"
        $destOnlyDb = "dbatoolsci_w6028_dstonly"

        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "CREATE DATABASE $db1"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "CREATE DATABASE $db2"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Query "CREATE DATABASE $sharedDb"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query "CREATE DATABASE $sharedDb"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Query "CREATE DATABASE $destOnlyDb"

        $neededSource = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $db1, $db2, $sharedDb
        $neededDest = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $sharedDb, $destOnlyDb
        $setupright = $true
        if ($neededSource.Count -ne 3 -or $neededDest.Count -ne 2) {
            $setupright = $false
        }
        # The first instance must not carry the dest-only database, or the carrier leg's absence
        # assertion is satisfied by the wrong reason.
        $destOnlyOnSource = @(Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $destOnlyDb -EnableException:$false)

        $sourceMajor = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1).VersionMajor
        $destMajor = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2).VersionMajor

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $db1, $db2, $sharedDb -ErrorAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $sharedDb, $destOnlyDb -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When setup is successful" {
        It "Should have setup correctly" {
            $setupright | Should -Be $true
        }

        It "Should have left the dest-only database off the source" {
            $destOnlyOnSource.Count | Should -Be 0
        }

        It "Should be migrating to an instance that is not older than the source" {
            $destMajor | Should -BeGreaterOrEqual $sourceMajor
        }
    }

    Context "When no database filter is supplied" {
        BeforeAll {
            $allResults = @(Test-DbaMigrationConstraint -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2)
        }

        It "Should return a row for every user database" {
            $allResults.Count | Should -BeGreaterOrEqual 3
        }

        It "Should report all of them migratable" {
            foreach ($result in $allResults) {
                $result.IsMigratable | Should -Be $true
            }
        }

        It "Should skip the system databases" {
            @($allResults | Where-Object Database -in "master", "msdb", "tempdb", "model").Count | Should -Be 0
        }

        It "Should fill in both instance names and both versions" {
            $sample = $allResults | Where-Object Database -eq $db1
            $sample.SourceInstance | Should -Not -BeNullOrEmpty
            $sample.DestinationInstance | Should -Not -BeNullOrEmpty
            $sample.SourceVersion | Should -Match "\(\d+\.\d+"
            $sample.DestinationVersion | Should -Match "\(\d+\.\d+"
            $sample.Notes | Should -Be "Database can be migrated."
        }
    }

    Context "When a single database is named" {
        BeforeAll {
            $singleResult = @(Test-DbaMigrationConstraint -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Database $db1)
        }

        It "Should return exactly that database" {
            $singleResult.Count | Should -Be 1
            $singleResult[0].Database | Should -Be $db1
        }

        It "Should report it migratable with no features in use" {
            $singleResult[0].IsMigratable | Should -Be $true
            $singleResult[0].FeaturesInUse | Should -BeNullOrEmpty
        }
    }

    Context "When ExcludeDatabase is supplied" {
        BeforeAll {
            $splatExclude = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                Database        = $db1
                ExcludeDatabase = $db2
            }
            $excludeResults = @(Test-DbaMigrationConstraint @splatExclude -WarningAction SilentlyContinue)
        }

        It "Should honour the exclusion" {
            @($excludeResults | Where-Object Database -eq $db2).Count | Should -Be 0
        }

        # Pins upstream behaviour rather than endorsing it: the exclusion branch REPLACES the
        # database list with an unfiltered server enumeration, so it discards the -Database filter
        # and re-admits the system databases the no-filter path removes. A port that "fixed" this
        # would diverge from the shipping command.
        It "Should discard the Database filter and re-admit system databases" {
            @($excludeResults | Where-Object Database -eq $db1).Count | Should -Be 1
            @($excludeResults | Where-Object Database -eq $sharedDb).Count | Should -Be 1
            @($excludeResults | Where-Object Database -eq "master").Count | Should -Be 1
        }
    }

    Context "When several instances are piped in" {
        BeforeAll {
            $pipedInstances = @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)
            $splatPiped = @{
                Destination     = $TestConfig.InstanceCopy2
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
                EnableException = $false
            }
            $pipedResults = @($pipedInstances | Test-DbaMigrationConstraint @splatPiped)
            $secondRecordRows = @($pipedResults | Where-Object SourceInstance -eq $TestConfig.InstanceCopy2)
        }

        It "Should return rows for both records" {
            @($pipedResults | Where-Object SourceInstance -eq $TestConfig.InstanceCopy1).Count | Should -BeGreaterOrEqual 3
            @($secondRecordRows | Where-Object Database -eq $sharedDb).Count | Should -Be 1
        }

        # The distinguishing leg. $Database is a parameter variable the process body reassigns, and
        # the engine never rebinds it because it is not pipeline-bound, so the second record is
        # measured against the FIRST record's database list. The dest-only database is the tell:
        # it is a user database on the second instance, so a record that enumerated its own server
        # would have to report it, and a record walking the first record's list cannot.
        It "Should carry the first record's database list into the second record" {
            @($secondRecordRows | Where-Object Database -eq $destOnlyDb).Count | Should -Be 0
        }
    }

    Context "When a record in the middle of the pipe cannot connect" {
        BeforeAll {
            $splatMixed = @{
                Destination     = $TestConfig.InstanceCopy2
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
                EnableException = $false
            }
            $mixedRecords = @($TestConfig.InstanceCopy1, $TestConfig.InstanceUnreachable, $TestConfig.InstanceCopy2)
            $mixedResults = @($mixedRecords | Test-DbaMigrationConstraint @splatMixed)
        }

        # The source's process block never reads Test-FunctionInterrupt, so the connect failure on
        # the middle record must not silence the one after it. This is the leg that catches a hop
        # shell whose Interrupted prologue latches on the nested Stop-Function.
        It "Should still process the record after the failure" {
            $afterFailure = @($mixedResults | Where-Object SourceInstance -eq $TestConfig.InstanceCopy2)
            @($afterFailure | Where-Object Database -eq $sharedDb).Count | Should -Be 1
        }

        It "Should return nothing for the unreachable record" {
            @($mixedResults | Where-Object SourceInstance -eq $TestConfig.InstanceUnreachable).Count | Should -Be 0
        }
    }

    Context "When the source instance cannot be reached" {
        It "Should warn under its own name and return nothing" {
            $splatWarn = @{
                Source          = $TestConfig.InstanceUnreachable
                Destination     = $TestConfig.InstanceCopy2
                EnableException = $false
                WarningVariable = "unreachableWarnings"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $unreachableResults = @(Test-DbaMigrationConstraint @splatWarn)
            $unreachableResults.Count | Should -Be 0
            # Connect-DbaInstance warns under its own name first; this pins the command's own catch,
            # which is the call that carries -FunctionName through the compatibility hop.
            @($unreachableWarnings -match "\[$CommandName\] Failure").Count | Should -BeGreaterThan 0
        }

        It "Should throw under EnableException" {
            $splatThrow = @{
                Source        = $TestConfig.InstanceUnreachable
                Destination   = $TestConfig.InstanceCopy2
                WarningAction = "SilentlyContinue"
            }
            { Test-DbaMigrationConstraint @splatThrow -EnableException } | Should -Throw
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

`$resolved = Get-Command -Name Test-DbaMigrationConstraint -ErrorAction SilentlyContinue

`$splatResolveAll = @{

    Name        = "Test-DbaMigrationConstraint"

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
