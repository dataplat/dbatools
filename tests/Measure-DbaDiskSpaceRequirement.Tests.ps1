#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Measure-DbaDiskSpaceRequirement",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Database",
                "SourceSqlCredential",
                "Destination",
                "DestinationDatabase",
                "DestinationSqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should take every parameter from the pipeline by property name" {
            $parameters = (Get-Command $CommandName).Parameters
            foreach ($name in "Source", "Database", "SourceSqlCredential", "Destination", "DestinationDatabase", "DestinationSqlCredential", "Credential") {
                $attribute = $parameters[$name].Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] }
                $attribute.ValueFromPipelineByPropertyName | Should -BeTrue -Because "$name is what makes the CSV and query pipelines in the examples work"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $sourceDbName = "dbatoolsci_w6025_src"
        $destDbName   = "dbatoolsci_w6025_dst"
        $absentDbName = "dbatoolsci_w6025_absent"
        $dataLogical  = "dbatoolsci_w6025_data"
        $logLogical   = "dbatoolsci_w6025_log"
        $extraLogical = "dbatoolsci_w6025_extra"

        function Remove-W6025Database {
            param($SqlInstance, $DatabaseName)

            $query = "IF DB_ID('$DatabaseName') IS NOT NULL BEGIN ALTER DATABASE [$DatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$DatabaseName]; END"
            Invoke-DbaQuery -SqlInstance $SqlInstance -Database "master" -Query $query
        }

        foreach ($name in $sourceDbName, $destDbName, $absentDbName) {
            Remove-W6025Database -SqlInstance $TestConfig.InstanceCopy1 -DatabaseName $name
            Remove-W6025Database -SqlInstance $TestConfig.InstanceCopy2 -DatabaseName $name
        }

        $sourcePaths = Get-DbaDefaultPath -SqlInstance $TestConfig.InstanceCopy1
        $destPaths   = Get-DbaDefaultPath -SqlInstance $TestConfig.InstanceCopy2

        # The logical names have to MATCH across the two instances - the command pairs files by
        # logical name only, so a destination built by New-DbaDatabase (which names files after the
        # database) would never produce a "Source and Destination" row.
        $sourceCreate = "CREATE DATABASE [$sourceDbName] ON PRIMARY (NAME = N'$dataLogical', FILENAME = N'$($sourcePaths.Data)\$sourceDbName.mdf', SIZE = 16MB) LOG ON (NAME = N'$logLogical', FILENAME = N'$($sourcePaths.Log)\$sourceDbName.ldf', SIZE = 8MB)"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Database "master" -Query $sourceCreate

        # Deliberately smaller than the source data file so DifferenceSize is non-zero and signed.
        $destCreate = "CREATE DATABASE [$destDbName] ON PRIMARY (NAME = N'$dataLogical', FILENAME = N'$($destPaths.Data)\$destDbName.mdf', SIZE = 8MB) LOG ON (NAME = N'$logLogical', FILENAME = N'$($destPaths.Log)\$destDbName.ldf', SIZE = 8MB)"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database "master" -Query $destCreate

        $destExtra = "ALTER DATABASE [$destDbName] ADD FILE (NAME = N'$extraLogical', FILENAME = N'$($destPaths.Data)\${destDbName}_extra.ndf', SIZE = 8MB)"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database "master" -Query $destExtra

        $destLogPath = (Get-DbaDbFile -SqlInstance $TestConfig.InstanceCopy2 -Database $destDbName | Where-Object LogicalName -eq $logLogical).PhysicalName
        $destExtraPath = (Get-DbaDbFile -SqlInstance $TestConfig.InstanceCopy2 -Database $destDbName | Where-Object LogicalName -eq $extraLogical).PhysicalName

        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $destServer   = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        foreach ($name in $sourceDbName, $destDbName) {
            Remove-W6025Database -SqlInstance $TestConfig.InstanceCopy1 -DatabaseName $name
            Remove-W6025Database -SqlInstance $TestConfig.InstanceCopy2 -DatabaseName $name
        }
    }

    Context "When the destination database does not exist" {
        BeforeAll {
            $splatAbsent = @{
                Source              = $TestConfig.InstanceCopy1
                Database            = $sourceDbName
                Destination         = $TestConfig.InstanceCopy2
                DestinationDatabase = $absentDbName
            }
            $absentResults = Measure-DbaDiskSpaceRequirement @splatAbsent
        }

        It "Should return one row per source file" {
            @($absentResults).Count | Should -Be 2
        }

        It "Should report every file as Only on Source" {
            @($absentResults | Where-Object FileLocation -eq "Only on Source").Count | Should -Be 2
        }

        It "Should carry the requested destination database name onto every row" {
            @($absentResults | Where-Object DestinationDatabase -eq $absentDbName).Count | Should -Be 2
        }

        It "Should leave the destination file columns empty" {
            foreach ($row in $absentResults) {
                $row.DestinationFileName | Should -BeNullOrEmpty
                $row.DestinationFileSize.Byte | Should -Be 0
            }
        }

        It "Should report the whole source file as the difference" {
            foreach ($row in $absentResults) {
                $row.DifferenceSize.Byte | Should -Be $row.SourceFileSize.Byte
            }
        }

        It "Should identify both instances" {
            $absentResults[0].SourceDatabase | Should -Be $sourceDbName
            $absentResults[0].SourceSqlInstance | Should -Be $sourceServer.DomainInstanceName
            $absentResults[0].DestinationSqlInstance | Should -Be $destServer.DomainInstanceName
        }
    }

    Context "When the database exists on both instances" {
        BeforeAll {
            $splatBoth = @{
                Source              = $TestConfig.InstanceCopy1
                Database            = $sourceDbName
                Destination         = $TestConfig.InstanceCopy2
                DestinationDatabase = $destDbName
            }
            $bothResults = Measure-DbaDiskSpaceRequirement @splatBoth
            $bothData    = $bothResults | Where-Object SourceLogicalName -eq $dataLogical
        }

        It "Should pair both source files with their destination twins" {
            @($bothResults | Where-Object FileLocation -eq "Source and Destination").Count | Should -Be 2
        }

        It "Should report the destination size as a negative quantity" {
            $bothData.DestinationFileSize.Byte | Should -BeLessThan 0
        }

        It "Should report the difference as source minus destination" {
            $bothData.DifferenceSize.Byte | Should -Be ($bothData.SourceFileSize.Byte + $bothData.DestinationFileSize.Byte)
            $bothData.DifferenceSize.Byte | Should -BeGreaterThan 0
        }

        It "Should name the destination database and its physical file" {
            $bothData.DestinationDatabase | Should -Be $destDbName
            $bothData.DestinationFileName | Should -Match ([regex]::Escape("$destDbName.mdf"))
        }

        It "Should report a destination-only file as Only on Destination" {
            $extraRow = $bothResults | Where-Object FileLocation -eq "Only on Destination"
            @($extraRow).Count | Should -Be 1
            $extraRow.DestinationLogicalName | Should -Be $extraLogical
            $extraRow.SourceFileSize.Byte | Should -Be 0
            $extraRow.DifferenceSize.Byte | Should -BeLessThan 0
        }

        It "Should carry the source's DestinationFileName defect on the Only on Destination row" {
            # public/Measure-DbaDiskSpaceRequirement.ps1 builds this cell from $destFile - the inner
            # matching loop's variable, left holding the last file it paired - instead of
            # $destFileNotSource, which the lines either side of it use correctly. Filed on #34; the
            # port carries it verbatim, so the row names the destination LOG file, not the extra one.
            $extraRow = $bothResults | Where-Object FileLocation -eq "Only on Destination"
            $extraRow.DestinationFileName | Should -Be $destLogPath
            $extraRow.DestinationFileName | Should -Not -Be $destExtraPath
        }
    }

    Context "When DestinationDatabase is omitted" {
        BeforeAll {
            $splatSameName = @{
                Source      = $TestConfig.InstanceCopy1
                Database    = $sourceDbName
                Destination = $TestConfig.InstanceCopy2
            }
            $sameNameResults = Measure-DbaDiskSpaceRequirement @splatSameName
        }

        It "Should fall back to the source database name" {
            @($sameNameResults | Where-Object DestinationDatabase -eq $sourceDbName).Count | Should -Be 2
        }
    }

    Context "When several records are piped in" {
        BeforeAll {
            # Records one and two both find their destination database, so both reach the mount
            # point cache; record three does not, which is what exposes the carried $destFiles.
            $pipeRecords = @(
                [PSCustomObject]@{
                    Source              = $TestConfig.InstanceCopy1
                    Database            = $sourceDbName
                    Destination         = $TestConfig.InstanceCopy2
                    DestinationDatabase = $destDbName
                }
                [PSCustomObject]@{
                    Source              = $TestConfig.InstanceCopy1
                    Database            = $sourceDbName
                    Destination         = $TestConfig.InstanceCopy2
                    DestinationDatabase = $destDbName
                }
                [PSCustomObject]@{
                    Source              = $TestConfig.InstanceCopy1
                    Database            = $sourceDbName
                    Destination         = $TestConfig.InstanceCopy2
                    DestinationDatabase = $absentDbName
                }
            )
            $pipeAll     = $pipeRecords | Measure-DbaDiskSpaceRequirement -Verbose 4>&1
            $pipeVerbose = @($pipeAll | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            $pipeResults = @($pipeAll | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })
        }

        It "Should process every record" {
            # Write-Message prefixes the timestamp and command name, so this cannot anchor at ^.
            @($pipeVerbose -match "\[$sourceDbName\] -> ").Count | Should -Be 3
        }

        It "Should build the mount point cache only once for the whole pipeline" {
            # The cache is declared in the source's begin block, which runs once for the pipeline.
            # A port that rebuilt it per record would re-query CIM and log this line for records one
            # and two alike.
            @($pipeVerbose -match "cacheMP\[").Count | Should -Be 1
        }

        It "Should carry the previous record's destination file list into a record whose destination database is absent" {
            # $destFiles is assigned only inside the "database exists" branch, so the last record
            # walks the PREVIOUS record's destination files and reports them as paired rather than
            # emitting Only on Source. Filed on #34; reproducing it is what makes this a parity port
            # rather than a rewrite - a per-record hop with no carrier reports Only on Source here.
            @($pipeResults).Count | Should -Be 8
            @($pipeResults | Where-Object FileLocation -eq "Only on Source").Count | Should -Be 0

            # An Only on Destination row has no DestinationDatabase property at all - it carries
            # DestinationDatabaseName instead - so the FileLocation half of this filter is load
            # bearing, not decoration.
            $leaked = @($pipeResults | Where-Object { $PSItem.FileLocation -eq "Source and Destination" -and $null -eq $PSItem.DestinationDatabase })
            $leaked.Count | Should -Be 2
            $leaked[0].DestinationFileName | Should -Match ([regex]::Escape($destDbName))
        }
    }

    Context "When the source database does not exist" {
        BeforeAll {
            $splatNoDb = @{
                Source      = $TestConfig.InstanceCopy1
                Database    = "dbatoolsci_w6025_nosuchsource"
                Destination = $TestConfig.InstanceCopy2
            }
            $noDbWarnings = @()
            $noDbResults = Measure-DbaDiskSpaceRequirement @splatNoDb -WarningVariable noDbWarnings -WarningAction SilentlyContinue
        }

        It "Should return nothing and say nothing" {
            # The source's "database MUST exist on Source" guard tests Test-Bound 'Database' -not on
            # a Mandatory parameter, so it can never fire. Filed on #34 and carried verbatim: the
            # command goes quiet instead of reporting the missing database.
            @($noDbResults).Count | Should -Be 0
            @($noDbWarnings).Count | Should -Be 0
        }
    }

    Context "When an instance cannot be reached" {
        It "Should warn under its own name and emit nothing" {
            $unreachableWarnings = $null
            # The Describe's BeforeAll turns EnableException on for every *-Dba* call so a broken
            # fixture fails loudly; this is the one leg that needs the friendly-warning path.
            $splatWarn = @{
                Source          = $TestConfig.InstanceUnreachable
                Database        = $sourceDbName
                Destination     = $TestConfig.InstanceCopy2
                EnableException = $false
                WarningVariable = "unreachableWarnings"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $unreachableResults = Measure-DbaDiskSpaceRequirement @splatWarn
            @($unreachableResults).Count | Should -Be 0
            # Connect-DbaInstance warns under its own name first; this pins the command's own catch,
            # which is the call that carries -FunctionName through the compatibility hop.
            @($unreachableWarnings -match "\[$CommandName\] Failure").Count | Should -BeGreaterThan 0
        }

        It "Should throw under EnableException" {
            $splatThrow = @{
                Source        = $TestConfig.InstanceUnreachable
                Database      = $sourceDbName
                Destination   = $TestConfig.InstanceCopy2
                WarningAction = "SilentlyContinue"
            }
            { Measure-DbaDiskSpaceRequirement @splatThrow -EnableException } | Should -Throw
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
            # succeeds silently on a path that already exists and leaves its permissions alone, so
            # the one thing that must not happen is adopting somebody else's directory and
            # executing a script out of it.
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
`$resolved = Get-Command -Name Measure-DbaDiskSpaceRequirement -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Measure-DbaDiskSpaceRequirement"
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
