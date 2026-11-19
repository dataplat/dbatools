#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only lists files.

# Expected values below are as the pin measured on both editions: evidence/pin-file-20261104.txt, whose case names the comments use.
# The fixture is one folder tree with a unique name on $TestConfig.Temp, the share every lab instance and this host reach, removed in AfterAll.
# A failed connect writes one warning line naming the server, where the pin writes two: an accepted difference,
# harness-edits.md, "Script-scope preferences and the one-line connect warning", points 5 to 7.

BeforeAll {
    # A plain call in a runspace of its own, so no try of Pester's encloses it, with a next statement after it. -Piped sends -Values down the pipeline.
    function Invoke-NativeOutsideTry {
        param([hashtable]$Arguments = @{ }, [object[]]$Values, [switch]$Piped)
        $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $outsideType = (Get-Command Get-DbaFile -CommandType Cmdlet).ImplementingType
        $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaFile", $outsideType, $null
        $outsideState.Commands.Add($outsideEntry)
        $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
        $outsideShell = [System.Management.Automation.PowerShell]::Create()
        $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
        $outsideStop = $null
        try {
            $outsideRunspace.Open()
            $outsideShell.Runspace = $outsideRunspace
            if ($Piped) {
                $null = $outsideShell.AddScript('param($Arguments, $Values) $Values | Get-DbaFile @Arguments; "next statement"').AddArgument($Arguments).AddArgument($Values)
            } else {
                $null = $outsideShell.AddScript('param($Arguments) Get-DbaFile @Arguments; "next statement"').AddArgument($Arguments)
            }
            try {
                $null = $outsideShell.Invoke($null, $outsideOutput)
            } catch {
                # The stop leaves the runspace's script through Invoke, as a method call's exception.
                $outsideStop = $PSItem.Exception.InnerException
            }
            [pscustomobject]@{
                Rows     = @($outsideOutput | Where-Object { $null -ne $PSItem.PSObject.Properties["Filename"] })
                Next     = @($outsideOutput | Where-Object { "$($PSItem.PSObject.BaseObject)" -ceq "next statement" }).Count -gt 0
                Errors   = @($outsideShell.Streams.Error)
                Warnings = @($outsideShell.Streams.Warning)
                Stop     = $outsideStop
            }
        } finally {
            $outsideShell.Dispose()
            $outsideRunspace.Dispose()
        }
    }

    # The record of a $server.ConnectionContext.ExecuteWithResults that faulted, as overflow-plain measured it.
    function Assert-NativeQueryFault {
        param($Record)
        $Record.FullyQualifiedErrorId | Should -BeLike "ExecutionFailureException*"
        "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
        $Record.CategoryInfo.Reason | Should -BeExactly "MethodInvocationException"
        $Record.TargetObject | Should -BeNullOrEmpty
        $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.MethodInvocationException"
        $Record.Exception.Message | Should -BeExactly "Exception calling `"ExecuteWithResults`" with `"1`" argument(s): `"An exception occurred while executing a Transact-SQL statement or batch.`""
        $Record.Exception.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Common.ExecutionFailureException"
    }
}

Describe "Native Get-DbaFile" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $missingInstance = "nativefile$(Get-Random)"
        $root = Join-Path $TestConfig.Temp "dbatoolsci_nfile_$(Get-Random)"
        $quoteDir = Join-Path $root "q'uote"
        $dollarDir = Join-Path $root ('d$_ollar')
        $omegaDir = Join-Path $root ([string][char]0x03A9 + "mega")
        $oneDir = Join-Path $root "one"
        $subDir = Join-Path $root "sub"
        foreach ($folder in $root, $subDir, $quoteDir, $dollarDir, $omegaDir, $oneDir) {
            $null = New-Item -Path $folder -ItemType Directory -ErrorAction Stop
        }
        foreach ($file in (Join-Path $root "top.txt"), (Join-Path $root "top.bak"), (Join-Path $subDir "deep.txt"), (Join-Path $quoteDir "inq.txt"), (Join-Path $dollarDir "ind.txt"), (Join-Path $omegaDir "ino.txt"), (Join-Path $oneDir "only.txt")) {
            Set-Content -LiteralPath $file -Value "dbatoolsci" -ErrorAction Stop
        }
        # Everything directly under the root, as the instance lists it at depth 1: the folders and the two files.
        $rootChildren = @($oneDir, $quoteDir, $dollarDir, $subDir, $omegaDir, (Join-Path $root "top.bak"), (Join-Path $root "top.txt"))
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
    }

    AfterAll {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Output" {
        # shape-unc.
        It "returns the pinned properties and default view" {
            $result = @(Get-DbaFile -SqlInstance $instance -Path $root -FileType txt -EnableException)
            $result.Count | Should -Be 1
            @($result[0].PSObject.Properties.Name) | Should -Be @("ComputerName", "InstanceName", "SqlInstance", "Filename", "RemoteFilename")
            @($result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Be @("Filename", "SqlInstance")
            $result[0].ComputerName | Should -BeExactly $server.ComputerName
            $result[0].InstanceName | Should -BeExactly $server.ServiceName
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result[0].Filename | Should -BeExactly (Join-Path $root "top.txt")
            # A path already on a share is its own remote name.
            $result[0].RemoteFilename | Should -BeExactly $result[0].Filename
        }

        # default-path.
        It "lists the default data directory when no -Path is given, each with its admin share name" {
            $dataPath = (Get-DbaDefaultPath -SqlInstance $instance -EnableException).Data
            $result = @(Get-DbaFile -SqlInstance $instance -EnableException)
            $result.Count | Should -BeGreaterThan 0
            foreach ($row in $result) {
                $row.Filename | Should -BeLike "$dataPath\*"
                $row.RemoteFilename | Should -BeExactly ("\\" + $server.ComputerName.Split("\")[0] + "\" + $row.Filename.Replace(":", "$"))
            }
        }
    }

    Context "-Depth and -FileType" {
        # unc-filetype-depth2.
        It "lists files two levels down with -Depth 2" {
            $result = @(Get-DbaFile -SqlInstance $instance -Path $root -Depth 2 -FileType txt -EnableException)
            @($result.Filename | Sort-Object) | Should -Be @(@((Join-Path $root "top.txt"), (Join-Path $subDir "deep.txt"), (Join-Path $quoteDir "inq.txt"), (Join-Path $dollarDir "ind.txt"), (Join-Path $omegaDir "ino.txt"), (Join-Path $oneDir "only.txt")) | Sort-Object)
        }

        It "matches extensions without regard to case, once for a repeated one" {
            $result = @(Get-DbaFile -SqlInstance $instance -Path $root -FileType TXT, txt, bak -EnableException)
            @($result.Filename | Sort-Object) | Should -Be @((Join-Path $root "top.bak"), (Join-Path $root "top.txt"))
        }

        # filetype-dot.
        It "matches nothing for an extension given with its dot" {
            @(Get-DbaFile -SqlInstance $instance -Path $root -FileType ".txt" -EnableException).Count | Should -Be 0
        }

        # filetype-empty, filetype-empties.
        It "filters nothing when every extension is empty" {
            $all = @(Get-DbaFile -SqlInstance $instance -Path $root -EnableException)
            $all.Count | Should -Be $rootChildren.Count
            $oneEmpty = @(Get-DbaFile -SqlInstance $instance -Path $root -FileType "" -EnableException)
            @($oneEmpty.Filename) | Should -Be @($all.Filename)
            $twoEmpty = @(Get-DbaFile -SqlInstance $instance -Path $root -FileType "", "" -EnableException)
            @($twoEmpty.Filename) | Should -Be @($all.Filename)
        }

        # two-paths.
        It "lists each path given, in the order of the query" {
            $result = @(Get-DbaFile -SqlInstance $instance -Path $oneDir, $root -FileType txt -EnableException)
            @($result.Filename | Sort-Object) | Should -Be @(@((Join-Path $oneDir "only.txt"), (Join-Path $root "top.txt")) | Sort-Object)
        }

        # path-empty, path-missing.
        It "lists nothing and writes nothing for an empty path and for a path that does not exist" {
            foreach ($value in "", (Join-Path $root "nothere")) {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $instance; Path = $value }
                $outside.Rows.Count | Should -Be 0
                $outside.Errors.Count | Should -Be 0
                $outside.Next | Should -BeTrue
            }
        }
    }

    # Correction unc-path: without -FileType the pin turned the leading \\ of a share into one \ (unc-plain), where -FileType keeps it (unc-filetype).
    Context "A share path without -FileType" {
        It "keeps the leading \\ of a share path without -FileType" {
            $result = @(Get-DbaFile -SqlInstance $instance -Path $root -EnableException)
            @($result.Filename | Sort-Object) | Should -Be @($rootChildren | Sort-Object)
            foreach ($row in $result) {
                $row.RemoteFilename | Should -BeExactly $row.Filename
            }
        }
    }

    # Correction path-literal: the path goes into the batch as one N'' string literal with its quotes doubled, whatever text it holds (quote, quote-injection, omega).
    Context "Path text the batch must keep as text" {
        It "reads a path holding a quote" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $instance; Path = $quoteDir; FileType = "txt" }
            $outside.Errors.Count | Should -Be 0
            @($outside.Rows.Filename) | Should -Be @(Join-Path $quoteDir "inq.txt")
        }

        It "runs no statement from the text of -Path" {
            $injection = "x'; INSERT #DirectoryTree (subdirectory,depth,isfile) VALUES (N'C:\dbatoolsci',0,0), (N'injected.txt',1,1); --"
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $instance; Path = $injection }
            @($outside.Rows | Where-Object Filename -like "*injected*").Count | Should -Be 0
            $outside.Rows.Count | Should -Be 0
        }

        It "reads a path holding a character outside the server's code page" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $instance; Path = $omegaDir; FileType = "txt" }
            $outside.Errors.Count | Should -Be 0
            @($outside.Rows.Filename) | Should -Be @(Join-Path $omegaDir "ino.txt")
        }
    }

    # Correction dollar-path: the pin put the path in with -Replace, whose replacement text reads $_ as the whole query block (dollar).
    Context "Path text with a dollar substitution" {
        It "reads a path holding a dollar and an underscore" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $instance; Path = $dollarDir; FileType = "txt" }
            $outside.Errors.Count | Should -Be 0
            @($outside.Rows.Filename) | Should -Be @(Join-Path $dollarDir "ind.txt")
        }
    }

    # Correction file-count: the pin's count read $datatable.Rows.Count, which is 0 for one row (one-row-verbose).
    Context "The verbose count" {
        It "reports the count of a single row" {
            $messages = @(Get-DbaFile -SqlInstance $instance -Path $oneDir -Verbose -EnableException 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            @($messages | Where-Object { $PSItem -match "(^|\D)1 files found\.$" }).Count | Should -Be 1
            @($messages | Where-Object { $PSItem -match "(^|\D)0 files found\.$" }).Count | Should -Be 0
        }

        # zero-row-verbose, many-row-verbose.
        It "reports no rows and many rows as counted" {
            $none = @(Get-DbaFile -SqlInstance $instance -Path (Join-Path $root "nothere") -Verbose -EnableException 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            @($none | Where-Object { $PSItem -match "(^|\D)0 files found\.$" }).Count | Should -Be 1
            $many = @(Get-DbaFile -SqlInstance $instance -Path $root -Verbose -EnableException 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            @($many | Where-Object { $PSItem -match "(^|\D)$($rootChildren.Count) files found\.$" }).Count | Should -Be 1
        }
    }

    # A -Depth past SMALLINT faults the batch (overflow-*): the pin writes the record outside any try and goes on.
    Context "A query that faults" {
        BeforeAll {
            $overflow = @{ SqlInstance = $instance; Path = $root; Depth = 40000 }
        }

        # overflow-plain, overflow-two.
        It "outside any try, writes the pinned record and goes on" {
            $outside = Invoke-NativeOutsideTry $overflow
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeQueryFault -Record $outside.Errors[0]
            $outside.Errors[0].Exception.GetBaseException().Message | Should -BeLike "Arithmetic overflow error*"
            $outside.Rows.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 0
            $outside.Next | Should -BeTrue
            (Invoke-NativeOutsideTry @{ SqlInstance = $instance, $instance; Path = $root; Depth = 40000 }).Errors.Count | Should -Be 2
        }

        # overflow-silent.
        It "outside any try, -ErrorAction SilentlyContinue writes no record and goes on" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $instance; Path = $root; Depth = 40000; ErrorAction = "SilentlyContinue" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        # overflow-ee: the pin writes the record and goes on; an accepted difference, the keep-going section's point 3.
        It "outside any try, -EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $instance, $instance; Path = $root; Depth = 40000; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeQueryFault -Record $outside.Errors[0]
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        # overflow-stop: an accepted difference, the stop PowerShell gives WriteError.
        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $instance; Path = $root; Depth = 40000; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Next | Should -BeFalse
        }

        # overflow-try, overflow-ee-try.
        It "inside a caller's try, the catch receives the record and the command does not go on" {
            foreach ($splatFault in @{ }, @{ EnableException = $true }) {
                $failure = $null
                $after = $false
                try {
                    $null = Get-DbaFile -SqlInstance $instance, $instance -Path $root -Depth 40000 @splatFault
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                Assert-NativeQueryFault -Record $failure
                $after | Should -BeFalse
            }
        }

        # overflow-stop-try.
        It "inside a caller's try, -ErrorAction Stop reaches the catch" {
            $failure = $null
            try {
                $null = Get-DbaFile -SqlInstance $instance -Path $root -Depth 40000 -ErrorAction Stop
            } catch {
                $failure = $PSItem
            }
            Assert-NativeQueryFault -Record $failure
        }
    }

    Context "Instances" {
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            @($instance, $instance | Get-DbaFile -Path $root -FileType txt -EnableException).Count | Should -Be 2
        }

        It "reads each instance of an array" {
            @(Get-DbaFile -SqlInstance $instance, $instance -Path $root -FileType txt -EnableException).Count | Should -Be 2
        }

        It "reads through a server object" {
            $result = @($server | Get-DbaFile -Path $root -FileType txt -EnableException)
            $result.Count | Should -Be 1
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
        }
    }

    Context "An instance that cannot be reached" {
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = $null
            $results = @(Get-DbaFile -SqlInstance $missingInstance, $instance -Path $root -FileType txt -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaFile\] Failure \| Error connecting to \[$missingInstance\]: "
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $results = @(Get-DbaFile -SqlInstance $missingInstance, $instance -Path $root -FileType txt -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
        }

        It "throws the connection failure under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $warnings = $null
            try {
                $null = Get-DbaFile -SqlInstance $missingInstance, $instance -Path $root -FileType txt -EnableException -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaFile\] Failure \| Error connecting to \[$missingInstance\]: "
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaFile*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($caught.TargetObject)" | Should -BeExactly $missingInstance
            @($collected).Count | Should -Be 0
        }
    }
}

Describe "Native Get-DbaFile on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 or times out (-2, 258) while it resumes, and the lab's mobile internet can drop a name lookup (11001, "No such host is known").
                $azureError = $PSItem.Exception
                $isResuming = "$($PSItem.Exception.Message)" -like "*timed out*"
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 258, 11001 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }

        $instance = $TestConfig.InstanceSingle
        $azureRoot = Join-Path $TestConfig.Temp "dbatoolsci_nfilea_$(Get-Random)"
        $null = New-Item -Path $azureRoot -ItemType Directory -ErrorAction Stop
        Set-Content -LiteralPath (Join-Path $azureRoot "only.txt") -Value "dbatoolsci" -ErrorAction Stop
        $refusalLine = "*Failure | *Azure SQL Database not supported*"
    }

    AfterAll {
        Remove-Item -LiteralPath $azureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Azure SQL Database has no extended stored procedures and no file system access (Learn, "Features comparison: Azure SQL Database and Azure SQL
    # Managed Instance"). The pin connected and xp_dirtree faulted (azure-path, azure-then-good, azure-ee, azure-try); the port refuses it as
    # Connect-DbaInstance -AzureUnsupported does (correction azure-refusal).
    It "refuses Azure SQL Database, which has no xp_dirtree, and goes on to the next instance" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($azureServer, $instance); Path = $azureRoot; FileType = "txt" }
        $outside.Stop | Should -BeNullOrEmpty
        $outside.Warnings.Count | Should -Be 1
        "$($outside.Warnings[0])" | Should -BeLike $refusalLine
        $outside.Errors.Count | Should -Be 0
        @($outside.Rows.Filename) | Should -Be @(Join-Path $azureRoot "only.txt")
        $outside.Next | Should -BeTrue
    }

    # azure-default.
    It "refuses Azure SQL Database on a connection by name" {
        $warnings = $null
        $results = @(Get-DbaFile -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -WarningVariable warnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
        $results.Count | Should -Be 0
        @($warnings).Count | Should -Be 1
        "$($warnings[0])" | Should -BeLike $refusalLine
    }

    It "throws the refusal under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
        $caught = $null
        $collected = $null
        try {
            $null = Get-DbaFile -SqlInstance $azureServer, $instance -Path $azureRoot -EnableException -OutVariable collected -WarningAction SilentlyContinue
        } catch {
            $caught = $PSItem
        }
        $caught.Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
        $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaFile*"
        "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        @($collected).Count | Should -Be 0
    }
}

Describe "Native Get-DbaFile over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        # Unique per leg and run: the share and the instance are shared.
        $loginRoot = Join-Path $TestConfig.Temp "dbatoolsci_nfilel_$(Get-Random)"
        $null = New-Item -Path $loginRoot -ItemType Directory -ErrorAction Stop
        Set-Content -LiteralPath (Join-Path $loginRoot "only.txt") -Value "dbatoolsci" -ErrorAction Stop
        $lowName = "dbatoolsci_nfile_low_$(Get-Random)"
        $lowPassword = "Nfile-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        # The fixture's connections below are passed only where a test names them.
        $fixture = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $null = $fixture.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$lowName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        $null = $fixture.ConnectionContext.ExecuteNonQuery("USE [master]; CREATE USER [$lowName] FOR LOGIN [$lowName]; DENY EXECUTE ON sys.xp_dirtree TO [$lowName];")
        $goodConnection = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $lowConnection = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred -NonPooledConnection -EnableException
    }

    AfterAll {
        Remove-Item -LiteralPath $loginRoot -Recurse -Force -ErrorAction SilentlyContinue
        # A connect that failed in BeforeAll leaves its variable empty; the login is still dropped below.
        foreach ($connection in $goodConnection, $lowConnection) {
            if ($null -ne $connection) {
                $connection.ConnectionContext.Disconnect()
            }
        }
        [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
        if ($null -eq $fixture) {
            return
        }
        foreach ($row in @($fixture.ConnectionContext.ExecuteWithResults("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';").Tables[0].Rows)) {
            try {
                $null = $fixture.ConnectionContext.ExecuteNonQuery("KILL $($row["session_id"]);")
            } catch {
                # A session this block has just disconnected can end between the read above and this KILL (error 6106); it then needs none.
                if ("$($PSItem.Exception.GetBaseException().Message)" -notlike "*is not an active process ID*") {
                    throw
                }
            }
        }
        $null = $fixture.ConnectionContext.ExecuteNonQuery("USE [master]; IF USER_ID(N'$lowName') IS NOT NULL DROP USER [$lowName];")
        $null = $fixture.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        $fixture.ConnectionContext.Disconnect()
    }

    # Correction stale-rows: in the pin a faulted query left $datatable as the call before it set it, so that call's rows came out again
    # under the faulted instance's name (good-then-denied-named, good-then-denied-piped).
    Context "A login denied xp_dirtree after one that may run it" {
        It "returns no rows of the call before a faulted query, named and piped" {
            $alone = @(Get-DbaFile -SqlInstance $goodConnection -Path $loginRoot -FileType txt -EnableException)
            $alone.Count | Should -Be 1
            $named = Invoke-NativeOutsideTry @{ SqlInstance = @($goodConnection, $lowConnection); Path = $loginRoot; FileType = "txt" }
            $piped = Invoke-NativeOutsideTry @{ Path = $loginRoot; FileType = "txt" } -Values @($goodConnection, $lowConnection) -Piped
            foreach ($outside in $named, $piped) {
                $outside.Errors.Count | Should -Be 1
                Assert-NativeQueryFault -Record $outside.Errors[0]
                $outside.Rows.Count | Should -Be 1
                $outside.Next | Should -BeTrue
            }
        }

        # denied-then-good-named.
        It "reads the instance after a faulted query" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($lowConnection, $goodConnection); Path = $loginRoot; FileType = "txt" }
            $outside.Errors.Count | Should -Be 1
            @($outside.Rows.Filename) | Should -Be @(Join-Path $loginRoot "only.txt")
            $outside.Next | Should -BeTrue
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        # by-name.
        It "works with -SqlCredential" {
            $result = @(Get-DbaFile -SqlInstance $loginInstance -SqlCredential $loginCred -Path $loginRoot -FileType txt -EnableException)
            @($result.Filename) | Should -Be @(Join-Path $loginRoot "only.txt")
        }

        # no-credential.
        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $result = Get-DbaFile -SqlInstance $loginInstance -Path $loginRoot -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaFile\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed")
        }

        # no-credential-ee.
        It "throws the connection failure under -EnableException" {
            { Get-DbaFile -SqlInstance $loginInstance -Path $loginRoot -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaFile*"
        }
    }
}
