#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaDbViewData",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "AutoCreateTable",
                "BatchSize",
                "BulkCopyTimeOut",
                "CheckConstraints",
                "Database",
                "Destination",
                "DestinationDatabase",
                "DestinationSqlCredential",
                "DestinationTable",
                "EnableException",
                "FireTriggers",
                "InputObject",
                "KeepIdentity",
                "KeepNulls",
                "NoTableLock",
                "NotifyAfter",
                "Query",
                "SqlCredential",
                "SqlInstance",
                "ScriptingOptionsObject",
                "Truncate",
                "View"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        function Remove-TempObjects {
            param ($dbs)
            function Remove-TempObject {
                param ($db, $object)
                $db.Query("DECLARE @obj int = OBJECT_ID('$object'); IF @obj IS NOT NULL
                BEGIN
                    IF (SELECT type_desc FROM sys.objects WHERE object_id = @obj) = 'VIEW' DROP VIEW $object
                    ELSE DROP TABLE $object
                END")
            }
            foreach ($d in $dbs) {
                Remove-TempObject $d dbo.dbatoolsci_example
                Remove-TempObject $d dbo.dbatoolsci_example2
                Remove-TempObject $d dbo.dbatoolsci_example3
                Remove-TempObject $d dbo.dbatoolsci_example4
                Remove-TempObject $d dbo.dbatoolsci_view_example
                Remove-TempObject $d dbo.dbatoolsci_view_example2
                Remove-TempObject $d dbo.dbatoolsci_view_example3
                Remove-TempObject $d dbo.dbatoolsci_view_example4
                Remove-TempObject $d dbo.dbatoolsci_view_will_exist
                Remove-TempObject $d dbo.dbatoolsci_view_example_table
                Remove-TempObject $d dbo.dbatoolsci_view_example2_table
                Remove-TempObject $d dbo.dbatoolsci_view_example3_table
                Remove-TempObject $d dbo.dbatoolsci_view_example4_table
                Remove-TempObject $d dbo.dbatoolsci_view_whatif_dest
                Remove-TempObject $d dbo.dbatoolsci_view_multi_dest
                Remove-TempObject $d dbo.dbatoolsci_view_timeout_dest
            }
        }

        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb
        $db2 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb
        Remove-TempObjects $db, $db2
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example (id int);
            INSERT dbo.dbatoolsci_example
            SELECT top 10 1
            FROM sys.objects")
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example2 (id int)")
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example3 (id int)")
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example4 (id int);
            INSERT dbo.dbatoolsci_example4
            SELECT top 13 1
            FROM sys.objects")
        $null = $db.Query("CREATE VIEW dbo.dbatoolsci_view_example AS SELECT * FROM dbo.dbatoolsci_example")
        $null = $db.Query("CREATE VIEW dbo.dbatoolsci_view_example2 AS SELECT * FROM dbo.dbatoolsci_example2")
        $null = $db.Query("CREATE VIEW dbo.dbatoolsci_view_example3 AS SELECT * FROM dbo.dbatoolsci_example3")
        $null = $db.Query("CREATE VIEW dbo.dbatoolsci_view_example4 AS SELECT * FROM dbo.dbatoolsci_example4")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_view_example (id int)")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_view_example3 (id int)")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_view_example4 (id int);
            INSERT dbo.dbatoolsci_view_example4
            SELECT top 13 2
            FROM sys.objects")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_view_whatif_dest (id int);
            INSERT dbo.dbatoolsci_view_whatif_dest
            SELECT top 3 2
            FROM sys.objects")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_view_multi_dest (id int)")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_view_timeout_dest (id int)")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-TempObjects $db, $db2

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "copies the view data" {
        $null = Copy-DbaDbViewData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -View dbatoolsci_view_example -DestinationTable dbatoolsci_example2
        $table1count = $db.Query("select id from dbo.dbatoolsci_view_example")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table1count.Status.Count | Should -Be $table2count.Status.Count
    }

    It "copies the view data to another instance" {
        $null = Copy-DbaDbViewData -SqlInstance $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Database tempdb -View dbatoolsci_view_example -DestinationTable dbatoolsci_view_example3
        $table1count = $db.Query("select id from dbo.dbatoolsci_view_example")
        $table2count = $db2.Query("select id from dbo.dbatoolsci_view_example3")
        $table1count.Status.Count | Should -Be $table2count.Status.Count
    }

    It "supports piping" {
        $null = Get-DbaDbView -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -View dbatoolsci_view_example | Copy-DbaDbViewData -DestinationTable dbatoolsci_example2 -Truncate
        $table1count = $db.Query("select id from dbo.dbatoolsci_view_example")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table1count.Status.Count | Should -Be $table2count.Status.Count
    }

    It "supports piping more than one view" {
        $results = Get-DbaDbView -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -View dbatoolsci_view_example2, dbatoolsci_view_example | Copy-DbaDbViewData -DestinationTable dbatoolsci_example3
        $results.Status.Count | Should -Be 2
        $results.RowsCopied | Measure-Object -Sum | Select-Object -ExpandProperty Sum | Should -Be 20
    }

    It "opens and closes connections properly" {
        #regression test, see #3468
        $results = Get-DbaDbView -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -View "dbo.dbatoolsci_view_example", "dbo.dbatoolsci_view_example4" | Copy-DbaDbViewData -Destination $TestConfig.InstanceCopy2 -DestinationDatabase tempdb -KeepIdentity -KeepNulls -BatchSize 5000 -Truncate
        $results.Status.Count | Should -Be 2
        $table1dbcount = $db.Query("select id from dbo.dbatoolsci_view_example")
        $table4dbcount = $db2.Query("select id from dbo.dbatoolsci_view_example4")
        $table1db2count = $db.Query("select id from dbo.dbatoolsci_view_example")
        $table4db2count = $db2.Query("select id from dbo.dbatoolsci_view_example4")
        $table1dbcount.Status.Count | Should -Be $table1db2count.Status.Count
        $table4dbcount.Status.Count | Should -Be $table4db2count.Status.Count
        $results[0].RowsCopied | Should -Be 10
        $results[1].RowsCopied | Should -Be 13
        $table4db2check = $db2.Query("select id from dbo.dbatoolsci_view_example4 where id = 1")
        $table4db2check.Status.Count | Should -Be 13
    }

    It "Should warn and return nothing if Source and Destination are same" {
        $result = Copy-DbaDbViewData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -View dbatoolsci_view_example -Truncate -WarningVariable tablewarning 3> $null
        $result | Should -Be $null
        $tablewarning | Should -Match "Cannot copy dbatoolsci_view_example into itself"
    }

    It "Should warn if the destination table doesn't exist" {
        $result = Copy-DbaDbViewData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -View tempdb.dbo.dbatoolsci_view_example -DestinationTable dbatoolsci_view_does_not_exist -WarningVariable tablewarning 3> $null
        $result | Should -Be $null
        $tablewarning | Should -Match Auto
    }

    It "automatically creates the table" {
        $result = Copy-DbaDbViewData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -View dbatoolsci_view_example -DestinationTable dbatoolsci_view_will_exist -AutoCreateTable
        $result.DestinationTable | Should -Be "dbatoolsci_view_will_exist"
    }

    It "Should warn if the source database doesn't exist" {
        $result = Copy-DbaDbViewData -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb_invalid -View dbatoolsci_view_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning 3> $null
        $result | Should -Be $null
        $tablewarning | Should -Match "Failure"
    }

    It "Copy data using a query that relies on the default source database" {
        $result = Copy-DbaDbViewData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -View dbatoolsci_view_example -Query "SELECT TOP (1) Id FROM dbo.dbatoolsci_view_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
        $result.RowsCopied | Should -Be 1
    }

    It "Copy data using a query that uses a 3 part query" {
        $result = Copy-DbaDbViewData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -View dbatoolsci_view_example -Query "SELECT TOP (1) Id FROM tempdb.dbo.dbatoolsci_view_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
        $result.RowsCopied | Should -Be 1
    }

    Context "When forwarding the caller's bound parameters" {
        It "Should neither truncate nor copy under -WhatIf, and should emit nothing" {
            $splatWhatIf = @{
                SqlInstance         = $TestConfig.InstanceCopy1
                Destination         = $TestConfig.InstanceCopy2
                Database            = "tempdb"
                DestinationDatabase = "tempdb"
                View                = "dbatoolsci_view_example"
                DestinationTable    = "dbatoolsci_view_whatif_dest"
                Truncate            = $true
                WhatIf              = $true
            }
            $result = Copy-DbaDbViewData @splatWhatIf
            $result | Should -BeNullOrEmpty

            $afterWhatIf = $db2.Query("SELECT id FROM dbo.dbatoolsci_view_whatif_dest")
            $afterWhatIf.Count | Should -Be 3
            @($afterWhatIf | Where-Object id -eq 2).Count | Should -Be 3
        }

        It "Should truncate and copy once -WhatIf is dropped" {
            # Without this the assertion above cannot fail: it would pass against a command that
            # forwards nothing at all.
            $splatReal = @{
                SqlInstance         = $TestConfig.InstanceCopy1
                Destination         = $TestConfig.InstanceCopy2
                Database            = "tempdb"
                DestinationDatabase = "tempdb"
                View                = "dbatoolsci_view_example"
                DestinationTable    = "dbatoolsci_view_whatif_dest"
                Truncate            = $true
            }
            $result = Copy-DbaDbViewData @splatReal
            $result.RowsCopied | Should -Be 10

            $afterReal = $db2.Query("SELECT id FROM dbo.dbatoolsci_view_whatif_dest")
            $afterReal.Count | Should -Be 10
            @($afterReal | Where-Object id -eq 2).Count | Should -Be 0
        }

        It "Should forward -BulkCopyTimeOut, which the receiving command spells BulkCopyTimeout" {
            # The two commands disagree on the capital O. The forward is a splat of the caller's
            # own bound set, so a receiver that did not bind the key case-insensitively would fail
            # the whole call rather than ignore the parameter.
            $splatTimeout = @{
                SqlInstance         = $TestConfig.InstanceCopy1
                Destination         = $TestConfig.InstanceCopy2
                Database            = "tempdb"
                DestinationDatabase = "tempdb"
                View                = "dbatoolsci_view_example"
                DestinationTable    = "dbatoolsci_view_timeout_dest"
                BulkCopyTimeOut     = 1200
                Truncate            = $true
            }
            $result = Copy-DbaDbViewData @splatTimeout
            $result.RowsCopied | Should -Be 10
            $db2.Query("SELECT id FROM dbo.dbatoolsci_view_timeout_dest").Count | Should -Be 10
        }

        It "Should forward -EnableException so a failure throws instead of warning" {
            $splatThrow = @{
                SqlInstance      = $TestConfig.InstanceCopy2
                Database         = "tempdb_invalid"
                View             = "dbatoolsci_view_example"
                DestinationTable = "dbatoolsci_doesntexist"
                EnableException  = $true
            }
            { Copy-DbaDbViewData @splatThrow } | Should -Throw
        }

        It "Should rebuild the forwarded set for every piped record" {
            # The bound set carries InputObject, and InputObject is the one parameter that changes
            # between records. A set captured once would send the first view twice, so the two
            # row counts have to differ for this to mean anything.
            $splatViewA = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = "tempdb"
                View        = "dbatoolsci_view_example"
            }
            $splatViewB = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = "tempdb"
                View        = "dbatoolsci_view_example4"
            }
            $pipedViewA = Get-DbaDbView @splatViewA
            $pipedViewB = Get-DbaDbView @splatViewB
            $pipedViewA | Should -Not -BeNullOrEmpty
            $pipedViewB | Should -Not -BeNullOrEmpty

            $splatMulti = @{
                Destination         = $TestConfig.InstanceCopy2
                DestinationDatabase = "tempdb"
                DestinationTable    = "dbatoolsci_view_multi_dest"
                Truncate            = $true
            }
            $results = $pipedViewA, $pipedViewB | Copy-DbaDbViewData @splatMulti
            $results.Count | Should -Be 2
            $results[0].SourceTable | Should -Be "dbatoolsci_view_example"
            $results[1].SourceTable | Should -Be "dbatoolsci_view_example4"
            $results[0].RowsCopied | Should -Be 10
            $results[1].RowsCopied | Should -Be 13
            $db2.Query("SELECT id FROM dbo.dbatoolsci_view_multi_dest").Count | Should -Be 13
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
`$resolved = Get-Command -Name Copy-DbaDbViewData -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaDbViewData"
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
