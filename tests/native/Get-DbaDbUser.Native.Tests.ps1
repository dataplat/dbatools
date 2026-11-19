#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbUser",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads database users.

# Expected values below are as the pin measured on both editions: evidence/pin-user-20261103.txt and evidence/pin-user2-20261103.txt. The case names in the comments are those files'.
# A failed connect writes one warning line naming the server, where the pin writes two: an accepted difference, harness-edits.md, "Script-scope preferences and the one-line
# connect warning", points 5 to 7. The two editions order the users of a database differently (usr*star), so names are compared sorted.

BeforeAll {
    function Format-NativeUserNames {
        param($Users)
        $names = [string[]]@($Users | ForEach-Object { $PSItem.Name })
        [array]::Sort($names, [System.StringComparer]::Ordinal)
        $names -join ","
    }
}

Describe "Native Get-DbaDbUser" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $stamp = Get-Random
        $dbA = "dbatoolsci_ndu_a_$stamp"
        $dbB = "dbatoolsci_ndu_b_$stamp"
        $dbOff = "dbatoolsci_ndu_off_$stamp"
        $dbCase = "dbatoolsci_ndu_cs_$stamp"
        $allDatabases = @($dbA, $dbB, $dbOff, $dbCase)
        $loginOne = "dbatoolsci_ndu_one_$stamp"
        $missingInstance = "nativedbuser$(Get-Random)"
        $allUsersA = "INFORMATION_SCHEMA,dbo,guest,sys,usr*star,usr_one,usr_orphan"

        # The reader of the independent values and the fixture's own connection; never given to the command unless a test says so.
        $server = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        $null = $server.Query("CREATE LOGIN [$loginOne] WITH PASSWORD = 'Ndu-$([guid]::NewGuid().ToString('N'))', CHECK_POLICY = OFF;")
        $null = $server.Query("CREATE DATABASE [$dbA]; CREATE DATABASE [$dbB]; CREATE DATABASE [$dbOff];")
        $null = $server.Query("CREATE DATABASE [$dbCase] COLLATE Latin1_General_CS_AS;")
        $null = $server.Query("USE [$dbA]; CREATE USER [usr_one] FOR LOGIN [$loginOne] WITH DEFAULT_SCHEMA = dbo; CREATE USER [usr_orphan] WITHOUT LOGIN; CREATE USER [usr*star] WITHOUT LOGIN; USE [master];")
        $null = $server.Query("USE [$dbB]; CREATE USER [usr_one] FOR LOGIN [$loginOne] WITH DEFAULT_SCHEMA = dbo; USE [master];")
        $null = $server.Query("USE [$dbCase]; CREATE USER [usrcase] WITHOUT LOGIN; CREATE USER [UsrCase] WITHOUT LOGIN; USE [master];")
        $null = $server.Query("ALTER DATABASE [$dbOff] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
    }

    AfterAll {
        $null = $server.Query("USE [master];")
        foreach ($name in $allDatabases) {
            $null = $server.Query("IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET ONLINE; ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
        }
        $null = $server.Query("IF SUSER_ID(N'$loginOne') IS NOT NULL DROP LOGIN [$loginOne];")
        $server.ConnectionContext.Disconnect()
    }

    Context "Output" {
        # shape
        It "returns the SMO user, with the pinned notes, view and values" {
            $engine = $server.Query("SELECT default_schema_name FROM [$dbA].sys.database_principals WHERE name = N'usr_one';")
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbA -User usr_one -EnableException)
            $result.Count | Should -Be 1
            $result[0].PSObject.BaseObject.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Smo.User"
            $result[0].PSObject.TypeNames[0] | Should -BeExactly "Microsoft.SqlServer.Management.Smo.User"
            @($result[0].PSObject.Properties | Where-Object MemberType -eq NoteProperty | ForEach-Object { $PSItem.Name }) | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Database")
            $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Database", "CreateDate", "DateLastModified", "Name", "Login", "LoginType", "AuthenticationType", "State", "HasDbAccess", "DefaultSchema")
            $result[0].ComputerName | Should -BeExactly $server.ComputerName
            $result[0].InstanceName | Should -BeExactly $server.ServiceName
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result[0].Database | Should -BeExactly $dbA
            $result[0].Name | Should -BeExactly "usr_one"
            $result[0].Login | Should -BeExactly $loginOne
            "$($result[0].LoginType)" | Should -BeExactly "SqlLogin"
            "$($result[0].State)" | Should -BeExactly "Existing"
            $result[0].HasDbAccess | Should -BeTrue
            $result[0].DefaultSchema | Should -BeExactly $engine.default_schema_name
        }

        # shape: the eight notes Get-DbaDatabase gives the database each user's Parent is.
        It "gives the parent database the pinned notes and values" {
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbA -User usr_one -EnableException)
            $parent = $result[0].Parent
            $parent.Name | Should -BeExactly $dbA
            @($parent.PSObject.Properties | Where-Object MemberType -eq NoteProperty | ForEach-Object { $PSItem.Name }) | Should -BeExactly @("BackupStatus", "ComputerName", "InstanceName", "SqlInstance", "LastRead", "LastWrite", "IsCdcEnabled", "Size")
            $parent.ComputerName | Should -BeExactly $server.ComputerName
            $parent.InstanceName | Should -BeExactly $server.ServiceName
            $parent.SqlInstance | Should -BeExactly $server.DomainInstanceName
            $parent.BackupStatus | Should -BeNullOrEmpty
            $parent.LastRead | Should -BeNullOrEmpty
            $parent.LastWrite | Should -BeNullOrEmpty
            $listed = $server.Query("SELECT d.is_cdc_enabled, SUM(CAST(f.size AS bigint)) * 8.0 / 1024 AS SizeMB FROM sys.databases AS d JOIN sys.master_files AS f ON f.database_id = d.database_id WHERE d.name = N'$dbA' GROUP BY d.is_cdc_enabled;")
            $parent.IsCdcEnabled | Should -BeOfType [bool]
            $parent.IsCdcEnabled | Should -Be $listed.is_cdc_enabled
            [math]::Abs([double]$parent.Size - [double]$listed.SizeMB) | Should -BeLessThan 1
        }

        # shape: a second call over the same connection adds the same members again.
        It "keeps four notes on a second call over the same connection, and eight on the parent" {
            $null = Get-DbaDbUser -SqlInstance $server -Database $dbA -User usr_one -EnableException
            $result = @(Get-DbaDbUser -SqlInstance $server -Database $dbA -User usr_one -EnableException)
            @($result[0].PSObject.Properties | Where-Object MemberType -eq NoteProperty).Count | Should -Be 4
            @($result[0].Parent.PSObject.Properties | Where-Object MemberType -eq NoteProperty).Count | Should -Be 8
        }
    }

    Context "User and system filters" {
        It "reads <Name>" -ForEach @(
            @{ Name = "every user with no filter"; Extra = @{ }; Expected = "INFORMATION_SCHEMA,dbo,guest,sys,usr*star,usr_one,usr_orphan" }
            @{ Name = "a named user"; Extra = @{ User = "usr_one" }; Expected = "usr_one" }
            @{ Name = "two named users"; Extra = @{ User = "usr_one", "usr_orphan" }; Expected = "usr_one,usr_orphan" }
            @{ Name = "a user in any case (user-any-case)"; Extra = @{ User = "USR_ONE" }; Expected = "usr_one" }
            @{ Name = "no user for a wildcard (user-wildcard)"; Extra = @{ User = "usr_*" }; Expected = "" }
            @{ Name = "a literal star in a name (user-literal-star)"; Extra = @{ User = "usr*star" }; Expected = "usr*star" }
            @{ Name = "no user for an absent name (user-none-match)"; Extra = @{ User = "nosuchuser" }; Expected = "" }
            @{ Name = "no user for an empty name (user-empty-string)"; Extra = @{ User = "" }; Expected = "" }
            @{ Name = "no user for an empty array (user-empty-array)"; Extra = @{ User = @() }; Expected = "" }
            @{ Name = "no user for a null (user-null)"; Extra = @{ User = $null }; Expected = "" }
            @{ Name = "the name beside a null element (user-null-and-name)"; Extra = @{ User = @($null, "usr_one") }; Expected = "usr_one" }
            @{ Name = "no login for a wildcard (login-wildcard)"; Extra = @{ Login = "dbatoolsci_ndu_*" }; Expected = "" }
            @{ Name = "every user with an empty login (login-empty-string)"; Extra = @{ Login = "" }; Expected = "INFORMATION_SCHEMA,guest,sys,usr*star,usr_orphan" }
            @{ Name = "no user for an empty login array (login-empty-array)"; Extra = @{ Login = @() }; Expected = "" }
            @{ Name = "no user for a null login (login-null)"; Extra = @{ Login = $null }; Expected = "" }
            @{ Name = "only the users that are not system objects (exclude-system)"; Extra = @{ ExcludeSystemUser = $true }; Expected = "usr*star,usr_one,usr_orphan" }
            @{ Name = "a system user dropped although it is named (exclude-system-and-system-name)"; Extra = @{ ExcludeSystemUser = $true; User = "dbo", "usr_one" }; Expected = "usr_one" }
        ) {
            $warnings = $null
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbA @Extra -WarningVariable warnings -EnableException)
            Format-NativeUserNames -Users $result | Should -BeExactly $Expected
            @($warnings).Count | Should -Be 0
        }

        # exclude-system-false
        It "keeps the system users when -ExcludeSystemUser is set to false" -Tag "NativeChecklist:switch-false" {
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbA -ExcludeSystemUser:$false -EnableException)
            Format-NativeUserNames -Users $result | Should -BeExactly $allUsersA
        }

        # login-one
        It "reads the users of a login, in each database" {
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbA, $dbB -Login $loginOne -EnableException)
            ($result.Database -join ",") | Should -BeExactly "$dbA,$dbB"
            ($result.Name -join ",") | Should -BeExactly "usr_one,usr_one"
        }

        # login-any-case
        It "reads the users of a login in any case" {
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbA -Login $loginOne.ToUpperInvariant() -EnableException)
            ($result.Name -join ",") | Should -BeExactly "usr_one"
        }

        # user-and-login
        It "applies -User and -Login together" {
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbA -User usr_one, usr_orphan -Login $loginOne -EnableException)
            ($result.Name -join ",") | Should -BeExactly "usr_one"
        }

        # case-sensitive-database, case-sensitive-any-case
        It "reads both users whose names differ only in case, and -User matches them in any case" {
            Format-NativeUserNames -Users @(Get-DbaDbUser -SqlInstance $instance -Database $dbCase -ExcludeSystemUser -EnableException) | Should -BeExactly "UsrCase,usrcase"
            Format-NativeUserNames -Users @(Get-DbaDbUser -SqlInstance $instance -Database $dbCase -User USRCASE -EnableException) | Should -BeExactly "UsrCase,usrcase"
        }
    }

    Context "Database filters" {
        # Correction database-wildcards: wildcard-database returns nothing on the pin, where the help says -Database supports wildcards.
        It "expands a wildcard in -Database" {
            $star = @(Get-DbaDbUser -SqlInstance $instance -Database "dbatoolsci_ndu_*_$stamp" -User usr_one -EnableException)
            ($star.Database -join ",") | Should -BeExactly "$dbA,$dbB"
            $single = @(Get-DbaDbUser -SqlInstance $instance -Database "dbatoolsci_ndu_?_$stamp" -User usr_one -EnableException)
            ($single.Database -join ",") | Should -BeExactly "$dbA,$dbB"
        }

        # The help documents no wildcard for -ExcludeDatabase: wildcard-exclude-database.
        It "keeps a wildcard in -ExcludeDatabase literal, so it excludes nothing" {
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbA, $dbB -ExcludeDatabase "dbatoolsci_ndu_b*" -User usr_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly "$dbA,$dbB"
        }

        # two-databases: named b then a, read in the order of the rows.
        It "reads the named databases in the order of the rows, not the order given" {
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbB, $dbA -User usr_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly "$dbA,$dbB"
        }

        # The pin selects from the rows of sys.databases; SMO's own collection is sorted, which would put model before tempdb.
        It "reads an instance-wide call in the order of the rows of sys.databases" {
            $rows = @($server.Query("SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases") | ForEach-Object { $PSItem.name })
            $shown = @(Get-DbaDbUser -SqlInstance $instance -User dbo -WarningAction SilentlyContinue | ForEach-Object { $PSItem.Database })
            $shown | Should -Contain $dbA
            $shown | Should -Not -Contain $dbOff
            ($shown -join ",") | Should -BeExactly (@($rows | Where-Object { $PSItem -in $shown }) -join ",")
            [array]::IndexOf($shown, "tempdb") | Should -BeLessThan ([array]::IndexOf($shown, "model"))
        }

        # database-any-case, database-absent, database-empty-string, database-null-element
        It "reads a database named in any case" {
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbA.ToUpperInvariant() -User usr_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly $dbA
        }

        It "reads nothing for an absent database, with no warning" {
            $warnings = $null
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database "dbatoolsci_ndu_absent_$stamp" -WarningVariable warnings -EnableException)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 0
        }

        It "reads every database for an empty name" {
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database "" -User usr_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly "$dbA,$dbB"
        }

        It "reads the name beside a null element" {
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database @($null, $dbB) -User usr_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly $dbB
        }

        # database-and-exclude, exclude-empty-string
        It "excludes a database named in any case" {
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbA, $dbB -ExcludeDatabase $dbB.ToUpperInvariant() -User usr_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly $dbA
        }

        It "excludes nothing for an empty name" {
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbA, $dbB -ExcludeDatabase "" -User usr_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly "$dbA,$dbB"
        }

        # offline-named
        It "skips an offline database silently" {
            $warnings = $null
            $result = @(Get-DbaDbUser -SqlInstance $instance -Database $dbOff, $dbB -User usr_one -WarningVariable warnings -EnableException)
            ($result.Database -join ",") | Should -BeExactly $dbB
            @($warnings).Count | Should -Be 0
        }
    }

    Context "Instances" {
        # piped-instance-twice
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $results = @($instance, $instance | Get-DbaDbUser -Database $dbA -User usr_one -EnableException)
            $results.Count | Should -Be 2
            $results[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            $results[1].SqlInstance | Should -BeExactly $server.DomainInstanceName
        }

        # named-instance-twice
        It "reads each instance of an array" {
            @(Get-DbaDbUser -SqlInstance $instance, $instance -Database $dbA -User usr_one -EnableException).Count | Should -Be 2
        }

        It "reads through a server object" {
            $result = @($server | Get-DbaDbUser -Database $dbA -User usr_one -EnableException)
            $result.Count | Should -Be 1
            $result[0].Name | Should -BeExactly "usr_one"
        }
    }

    Context "An instance that cannot be reached" {
        # bad-between
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = $null
            $results = @(Get-DbaDbUser -SqlInstance $missingInstance, $instance -Database $dbA -User usr_one -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbUser\] Failure \| Error connecting to \[$missingInstance\]: "
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $results = @(Get-DbaDbUser -SqlInstance $missingInstance, $instance -Database $dbA -User usr_one -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
        }

        # bad-ee
        It "throws the connection failure under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $warnings = $null
            try {
                $null = Get-DbaDbUser -SqlInstance $missingInstance, $instance -Database $dbA -EnableException -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbUser\] Failure \| Error connecting to \[$missingInstance\]: "
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbUser*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($caught.TargetObject)" | Should -BeExactly $missingInstance
            # The line names the server; the caught record stays the server's own message.
            $caught.Exception.Message | Should -Not -BeLike "*Error connecting to*"
            @($collected).Count | Should -Be 0
        }
    }

    # In a runspace of its own, where Streams.Warning can be read and nothing else sets a preference. Points 5 and 6 of the section named above.
    Context "The warning stream of a failed connect" {
        BeforeAll {
            $streamLine = "\[Get-DbaDbUser\] Failure \| Error connecting to \[$missingInstance\]: "
            $streamState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $streamRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($streamState)
            $streamRunspace.Open()
            $streamShell = [System.Management.Automation.PowerShell]::Create()
            $streamShell.Runspace = $streamRunspace
            $streamModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
            $null = $streamShell.AddCommand("Import-Module").AddParameter("Name", $streamModulePath).AddParameter("ErrorAction", "Stop").Invoke()

            function Invoke-NativeDbUserStream {
                param([string]$Script)
                $streamShell.Commands.Clear()
                $streamShell.Streams.Warning.Clear()
                $null = $streamShell.AddScript($Script).AddArgument($missingInstance)
                $output = @($streamShell.Invoke())
                [pscustomobject]@{
                    Lines    = @($output | Where-Object { $PSItem.psobject.BaseObject -is [string] } | ForEach-Object { "$PSItem" })
                    Merged   = @($output | Where-Object { $PSItem.psobject.BaseObject -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $PSItem.Message })
                    Warnings = @($streamShell.Streams.Warning | ForEach-Object { $PSItem.Message })
                }
            }
        }

        AfterAll {
            $streamShell.Dispose()
            $streamRunspace.Dispose()
        }

        It "holds the one line in the warning stream of a plain call, which goes on" {
            $call = Invoke-NativeDbUserStream -Script 'param($Target) Get-DbaDbUser -SqlInstance $Target; "next statement"'
            $call.Warnings.Count | Should -Be 1
            $call.Warnings[0] | Should -Match $streamLine
            $call.Lines | Should -Contain "next statement"
        }

        It "merges the one line under 3>&1 on a plain call" {
            $call = Invoke-NativeDbUserStream -Script 'param($Target) Get-DbaDbUser -SqlInstance $Target 3>&1; "next statement"'
            $call.Merged.Count | Should -Be 1
            $call.Merged[0] | Should -Match $streamLine
            $call.Warnings.Count | Should -Be 0
            $call.Lines | Should -Contain "next statement"
        }

        It "displays nothing under -EnableException, and -WarningVariable holds the one line" -Tag "NativeChecklist:enable-exception" {
            $call = Invoke-NativeDbUserStream -Script 'param($Target) try { Get-DbaDbUser -SqlInstance $Target -EnableException -WarningVariable held 3>&1 } catch { "caught " + $PSItem.FullyQualifiedErrorId }; "held " + @($held).Count; foreach ($line in $held) { "line " + $line }'
            $call.Merged.Count | Should -Be 0
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDbUser*" }).Count | Should -Be 1
            $call.Lines | Should -Contain "held 1"
            @($call.Lines | Where-Object { $PSItem -like "line *" -and $PSItem -match $streamLine }).Count | Should -Be 1
        }

        It "leaves the warning stream empty under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $call = Invoke-NativeDbUserStream -Script 'param($Target) try { Get-DbaDbUser -SqlInstance $Target -EnableException } catch { "caught " + $PSItem.FullyQualifiedErrorId }'
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDbUser*" }).Count | Should -Be 1
        }
    }

    Context "A null or empty -SqlInstance" {
        # instance-null, instance-empty, instance-null-element: the command's own binder refuses it, before any nested command.
        It "refuses <Name> at the binder, with no warning and no output" -ForEach @(
            @{ Name = "a null element"; Value = @($null, "unused"); Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "a null value"; Value = $null; Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "an empty array"; Value = @(); Id = "ParameterArgumentValidationErrorEmptyArrayNotAllowed"; Reason = "is an empty array" }
        ) {
            $caught = $null
            $warnings = $null
            $collected = $null
            try {
                $null = Get-DbaDbUser -SqlInstance $Value -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "$Id,*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
            $caught.Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it $Reason."
            # A binder refusal may leave these unset; @($null) would count 1.
            $warnings | Should -BeNullOrEmpty
            $collected | Should -BeNullOrEmpty
        }
    }
}

Describe "Native Get-DbaDbUser on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $azureDatabase = $TestConfig.AzureSqlDbName
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $azureDatabase
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 or times out (-2, 258) while it resumes, and the lab's mobile
                # internet can drop a name lookup (11001, "No such host is known").
                $azureError = $PSItem.Exception
                $isResuming = "$($azureError.Message)" -like "*timed out*"
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 258, 11001 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    # azure-connection, azure-shape: read-only, and the instance name is empty there.
    It "reads the users of the database of its connection" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = $null
        $result = @(Get-DbaDbUser -SqlInstance $azureServer -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 0
        Format-NativeUserNames -Users $result | Should -BeExactly "INFORMATION_SCHEMA,dbo,guest,sys"
        $result[0].PSObject.BaseObject.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Smo.User"
        @($result.Database | Select-Object -Unique) | Should -BeExactly @($azureDatabase)
        $result[0].ComputerName | Should -BeExactly $azureServer.ComputerName
        $result[0].InstanceName | Should -BeNullOrEmpty
        $result[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        # azure-shape: the same notes on the parent; Azure's database query has no is_cdc_enabled column.
        @($result[0].Parent.PSObject.Properties | Where-Object MemberType -eq NoteProperty | ForEach-Object { $PSItem.Name }) | Should -BeExactly @("BackupStatus", "ComputerName", "InstanceName", "SqlInstance", "LastRead", "LastWrite", "IsCdcEnabled", "Size")
        $result[0].Parent.IsCdcEnabled | Should -BeNullOrEmpty
    }

    # azure-exclude-system
    It "reads none of those with -ExcludeSystemUser" -Tag "NativeChecklist:azure-sqldb" {
        @(Get-DbaDbUser -SqlInstance $azureServer -ExcludeSystemUser -EnableException).Count | Should -Be 0
    }

    # azure-by-name: the order of the rows, master first, where SMO's collection is sorted.
    It "reads by name master and then the database, in the order of the rows" -Tag "NativeChecklist:azure-sqldb" {
        $result = @(Get-DbaDbUser -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -EnableException)
        (@($result.Database | Select-Object -Unique) -join ",") | Should -BeExactly "master,$azureDatabase"
    }

    # azure-by-name-database
    It "reads by name the one database asked for" -Tag "NativeChecklist:azure-sqldb" {
        $result = @(Get-DbaDbUser -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $azureDatabase -EnableException)
        Format-NativeUserNames -Users $result | Should -BeExactly "INFORMATION_SCHEMA,dbo,guest,sys"
        @($result.Database | Select-Object -Unique) | Should -BeExactly @($azureDatabase)
    }
}

Describe "Native Get-DbaDbUser over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        # Unique per leg and run: the instance is shared.
        $stamp = Get-Random
        $dbB = "dbatoolsci_ndul_b_$stamp"
        $dbNone = "dbatoolsci_ndul_none_$stamp"
        $dbHeld = "dbatoolsci_ndul_held_$stamp"
        $dbLow = "dbatoolsci_ndul_low_$stamp"
        $allDatabases = @($dbHeld, $dbB, $dbNone, $dbLow)
        $lowName = "dbatoolsci_ndul_low_$stamp"
        $lowPassword = "Ndu-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $heldText = "*Database '$dbHeld' is already open and can only have one user at a time."

        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = '$lowPassword', CHECK_POLICY = OFF;")
        foreach ($name in $allDatabases) {
            $null = $loginServer.Query("CREATE DATABASE [$name];")
            $null = $loginServer.Query("USE [$name]; CREATE USER [usr_one] WITHOUT LOGIN; USE [master];")
        }
        $null = $loginServer.Query("USE [$dbLow]; CREATE USER [$lowName] FOR LOGIN [$lowName]; USE [master];")

        # The connection the held cases pass: it has read both databases' properties, but not their users, and so keeps reading the held one as accessible (read after the hold).
        $measured = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $null = $measured.Databases[$dbHeld].IsAccessible
        $null = $measured.Databases[$dbB].IsAccessible
        $holder = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $holder.ConnectionContext.ExecuteNonQuery("USE [$dbHeld]; ALTER DATABASE [$dbHeld] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;")

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaDbUser -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbUser", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript('param($Arguments) Get-DbaDbUser @Arguments; "next statement"').AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Output   = @($outsideOutput)
                    Rows     = @($outsideOutput | Where-Object { $PSItem -isnot [string] })
                    Errors   = @($outsideShell.Streams.Error)
                    Warnings = @($outsideShell.Streams.Warning)
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }

        function Assert-NativeHeldRecord {
            param($Record)
            $Record.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator,*"
            "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $Record.CategoryInfo.Reason | Should -BeExactly "ExtendedTypeSystemException"
            $Record.TargetObject | Should -BeNullOrEmpty
            $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.ExtendedTypeSystemException"
            $Record.Exception.Message | Should -BeExactly 'The following exception occurred while trying to enumerate the collection: "An exception occurred while executing a Transact-SQL statement or batch.".'
            $Record.Exception.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Common.ExecutionFailureException"
            $Record.Exception.InnerException.InnerException.GetType().Name | Should -BeExactly "SqlException"
            $Record.Exception.InnerException.InnerException.Message | Should -BeLike $heldText
        }
    }

    AfterAll {
        foreach ($connection in @($measured, $holder)) {
            $connection.ConnectionContext.Disconnect()
        }
        foreach ($name in $allDatabases) {
            $null = $loginServer.Query("IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
        }
        # A query with no rows must not read as one null row.
        foreach ($row in @($loginServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';") | Where-Object { $null -ne $PSItem })) {
            $null = $loginServer.Query("KILL $($row.session_id);")
        }
        $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        $loginServer.ConnectionContext.Disconnect()
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaDbUser -SqlInstance $loginInstance -SqlCredential $loginCred -Database $dbB -User usr_one -EnableException)
            $result.Count | Should -Be 1
            $result[0].Database | Should -BeExactly $dbB
            $result[0].SqlInstance | Should -BeExactly $loginServer.DomainInstanceName
        }

        # no-credential
        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $result = Get-DbaDbUser -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaDbUser\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed")
        }

        # no-credential-ee
        It "throws the connection failure under -EnableException" {
            { Get-DbaDbUser -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDbUser*"
        }
    }

    Context "A login with little access" {
        # low-no-user
        It "reads nothing from a database it has no user in, with no warning" {
            $warnings = $null
            $result = @(Get-DbaDbUser -SqlInstance $loginInstance -SqlCredential $lowCred -Database $dbNone -WarningVariable warnings -EnableException)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 0
        }

        # low-user-no-permission: the other user of the database, usr_one, is not visible to it.
        It "reads the users it can see in a database it has a user in" {
            $result = @(Get-DbaDbUser -SqlInstance $loginInstance -SqlCredential $lowCred -Database $dbLow -EnableException)
            Format-NativeUserNames -Users $result | Should -BeExactly "INFORMATION_SCHEMA,$lowName,dbo,guest,sys"
        }

        # low-master
        It "reads the users it can see in master as guest" {
            $result = @(Get-DbaDbUser -SqlInstance $loginInstance -SqlCredential $lowCred -Database master -EnableException)
            Format-NativeUserNames -Users $result | Should -BeExactly "INFORMATION_SCHEMA,dbo,guest,sys"
        }
    }

    Context "A database held in single-user mode, on a connection that has not read it yet" {
        # held-named, its held-ee, held-stop and held-try: such a connection reads the database as not accessible, so -OnlyAccessible drops it silently.
        It "skips it silently: <Name>" -ForEach @(
            @{ Name = "plain"; Extra = @{ } }
            @{ Name = "-EnableException"; Extra = @{ EnableException = $true } }
            @{ Name = "-ErrorAction Stop"; Extra = @{ ErrorAction = "Stop" } }
        ) {
            $outside = Invoke-NativeOutsideTry (@{ SqlInstance = $loginInstance; SqlCredential = $loginCred; Database = @($dbHeld, $dbB); User = "usr_one" } + $Extra)
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 0
            $outside.Rows.Count | Should -Be 1
            $outside.Rows[0].Database | Should -BeExactly $dbB
        }
    }

    Context "A database held in single-user mode, on a connection that read it before, outside any try" {
        # held-plain, held-user, held-login, held-exclude-system, held-all-filters: one record for each statement that enumerates the users.
        It "a plain call writes <Records> record(s), goes on to the next database and the next statement: <Name>" -ForEach @(
            @{ Name = "no filter"; Extra = @{ }; Records = 1; Expected = "INFORMATION_SCHEMA,dbo,guest,sys,usr_one" }
            @{ Name = "-User"; Extra = @{ User = "usr_one" }; Records = 2; Expected = "usr_one" }
            @{ Name = "-Login"; Extra = @{ Login = "" }; Records = 2; Expected = "INFORMATION_SCHEMA,guest,sys,usr_one" }
            @{ Name = "-ExcludeSystemUser"; Extra = @{ ExcludeSystemUser = $true }; Records = 2; Expected = "usr_one" }
            @{ Name = "all three filters"; Extra = @{ ExcludeSystemUser = $true; User = "usr_one"; Login = "" }; Records = 4; Expected = "usr_one" }
        ) {
            $outside = Invoke-NativeOutsideTry (@{ SqlInstance = $measured; Database = @($dbHeld, $dbB) } + $Extra)
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be $Records
            foreach ($record in $outside.Errors) {
                Assert-NativeHeldRecord -Record $record
            }
            $outside.Warnings.Count | Should -Be 0
            Format-NativeUserNames -Users $outside.Rows | Should -BeExactly $Expected
            @($outside.Rows.Database | Select-Object -Unique) | Should -BeExactly @($dbB)
            $outside.Output[-1] | Should -BeExactly "next statement"
        }

        # held-silent
        It "-ErrorAction SilentlyContinue writes no record and goes on" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $measured; Database = @($dbHeld, $dbB); User = "usr_one"; ErrorAction = "SilentlyContinue" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            ($outside.Rows.Name -join ",") | Should -BeExactly "usr_one"
            $outside.Output[-1] | Should -BeExactly "next statement"
        }

        # Accepted difference, keep-going: held-ee goes on where the port stops.
        It "-EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $measured; Database = @($dbHeld, $dbB); User = "usr_one"; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeHeldRecord -Record $outside.Errors[0]
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        # Accepted difference, keep-going: held-stop ends the function's statement only.
        It "-ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $measured; Database = @($dbHeld, $dbB); User = "usr_one"; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeHeldRecord -Record $outside.Stop.ErrorRecord
            $outside.Output.Count | Should -Be 0
        }
    }

    Context "A database held in single-user mode, on a connection that read it before, inside a caller's try" {
        # held-try, held-user-try, held-ee-try, held-stop-try
        It "the catch receives the record and the command does not go on: <Name>" -ForEach @(
            @{ Name = "plain"; Extra = @{ } }
            @{ Name = "-User"; Extra = @{ User = "usr_one" } }
            @{ Name = "-EnableException"; Extra = @{ EnableException = $true } }
            @{ Name = "-ErrorAction Stop"; Extra = @{ ErrorAction = "Stop" } }
        ) {
            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            $after = $false
            try {
                Get-DbaDbUser -SqlInstance $measured -Database $dbHeld, $dbB @Extra | ForEach-Object { $null = $streamed.Add($PSItem) }
                $after = $true
            } catch {
                $failure = $PSItem
            }
            Assert-NativeHeldRecord -Record $failure
            $after | Should -BeFalse
            $streamed.Count | Should -Be 0
        }
    }
}
