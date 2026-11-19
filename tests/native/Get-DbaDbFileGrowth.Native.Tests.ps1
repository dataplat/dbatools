#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbFileGrowth",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.

Describe "Native database file growth behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeGrowthCreated = New-Object "System.Collections.Generic.List[string]"
        $splatNativeGrowthConnect = @{
            SqlInstance         = $TestConfig.InstanceSingle
            NonPooledConnection = $true
            EnableException     = $true
        }
        $nativeGrowthServer = Connect-DbaInstance @splatNativeGrowthConnect
        $nativeGrowthSuffix = [Guid]::NewGuid().ToString("N")
        $nativeGrowthName = "native_growth_$nativeGrowthSuffix"
        $nativeGrowthLegacyName = "native_growthlegacy_$nativeGrowthSuffix"
        $nativeGrowthDroppedName = "native_growthdrop_$nativeGrowthSuffix"
        $nativeGrowthGroupName = "native_growth_secondary"
        $nativeGrowthCappedName = "native_growth_capped_$nativeGrowthSuffix"

        foreach ($nativeGrowthNewName in $nativeGrowthName, $nativeGrowthLegacyName, $nativeGrowthDroppedName) {
            $null = $nativeGrowthServer.ConnectionContext.ExecuteNonQuery("CREATE DATABASE [$nativeGrowthNewName]")
            $nativeGrowthCreated.Add($nativeGrowthNewName)
        }

        $nativeGrowthPrimaryPath = $nativeGrowthServer.ConnectionContext.ExecuteScalar("SELECT physical_name FROM sys.master_files WHERE database_id = DB_ID(N'$nativeGrowthName') AND file_id = 1")
        $nativeGrowthDirectory = $nativeGrowthPrimaryPath.Substring(0, $nativeGrowthPrimaryPath.LastIndexOfAny([char[]]@("\", "/")) + 1)
        $nativeGrowthSetup = @(
            "ALTER DATABASE [$nativeGrowthName] MODIFY FILE (NAME = N'$nativeGrowthName', MAXSIZE = 512MB)",
            "ALTER DATABASE [$nativeGrowthName] MODIFY FILE (NAME = N'$nativeGrowthName', FILEGROWTH = 16MB)",
            "ALTER DATABASE [$nativeGrowthName] MODIFY FILE (NAME = N'$($nativeGrowthName)_log', FILEGROWTH = 10%)",
            "ALTER DATABASE [$nativeGrowthName] MODIFY FILE (NAME = N'$($nativeGrowthName)_log', MAXSIZE = UNLIMITED)",
            "ALTER DATABASE [$nativeGrowthName] ADD FILEGROUP [$nativeGrowthGroupName]",
            "ALTER DATABASE [$nativeGrowthName] ADD FILE (NAME = N'$nativeGrowthCappedName', FILENAME = N'$nativeGrowthDirectory$nativeGrowthCappedName.ndf', SIZE = 8MB, MAXSIZE = 10MB, FILEGROWTH = 4MB) TO FILEGROUP [$nativeGrowthGroupName]",
            "ALTER DATABASE [$nativeGrowthLegacyName] SET COMPATIBILITY_LEVEL = 100"
        )
        foreach ($nativeGrowthStatement in $nativeGrowthSetup) {
            $null = $nativeGrowthServer.ConnectionContext.ExecuteNonQuery($nativeGrowthStatement)
        }
        $nativeGrowthServer.Databases.Refresh()
        $nativeGrowthDatabase = $nativeGrowthServer.Databases[$nativeGrowthName]
        $nativeGrowthLegacy = $nativeGrowthServer.Databases[$nativeGrowthLegacyName]
        $nativeGrowthDisplay = "ComputerName,InstanceName,SqlInstance,Database,MaxSize,GrowthType,Growth,File,FileName,State"
        $nativeGrowthProperties = "ComputerName,InstanceName,SqlInstance,Database,DatabaseID,FileGroupName,ID,Type,TypeDescription,LogicalName,PhysicalName,State,MaxSize,Growth,GrowthType,NextGrowthEventSize,Size,UsedSpace,AvailableSpace,IsOffline,IsReadOnly,IsReadOnlyMedia,IsSparse,NumberOfDiskWrites,NumberOfDiskReads,ReadFromDisk,WrittenToDisk,VolumeFreeSpace,FileGroupDataSpaceId,FileGroupType,FileGroupTypeDescription,FileGroupDefault,FileGroupReadOnly,File,FileName"
    }

    AfterAll {
        $splatNativeGrowthCleanup = @{
            SqlInstance         = $TestConfig.InstanceSingle
            NonPooledConnection = $true
            EnableException     = $true
        }
        $nativeGrowthCleanupServer = Connect-DbaInstance @splatNativeGrowthCleanup
        foreach ($nativeGrowthCreatedName in $nativeGrowthCreated) {
            $null = $nativeGrowthCleanupServer.ConnectionContext.ExecuteNonQuery("IF DB_ID(N'$nativeGrowthCreatedName') IS NOT NULL BEGIN ALTER DATABASE [$nativeGrowthCreatedName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$nativeGrowthCreatedName]; END")
        }
        $nativeGrowthCleanupServer.ConnectionContext.Disconnect()
        if ($nativeGrowthServer) { $nativeGrowthServer.ConnectionContext.Disconnect() }
    }

    It "returns one typed row per file with computed growth, aliases and display set, and keeps the connection database" -Tag "NativeChecklist:switch-false" {
        $nativeGrowthContextBefore = $nativeGrowthServer.ConnectionContext.CurrentDatabase
        $splatNativeGrowthRead = @{
            SqlInstance     = $nativeGrowthServer
            Database        = $nativeGrowthName
            EnableException = $false
            Verbose         = $true
        }
        $nativeGrowthMessages = @(Get-DbaDbFileGrowth @splatNativeGrowthRead 4>&1)
        $nativeGrowthServer.ConnectionContext.CurrentDatabase | Should -BeExactly $nativeGrowthContextBefore
        $nativeGrowthRows = @($nativeGrowthMessages | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })
        $nativeGrowthRows.Count | Should -Be 3
        @($nativeGrowthMessages | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message.Contains("Querying database [$nativeGrowthName]") }).Count | Should -Be 1

        $nativeGrowthExpected = @{ }
        $nativeGrowthReadQuery = "SELECT file_id, name, size, max_size, growth, is_percent_growth FROM sys.database_files"
        foreach ($nativeGrowthExpectedRow in $nativeGrowthDatabase.ExecuteWithResults($nativeGrowthReadQuery).Tables[0].Rows) {
            $nativeGrowthExpected[[int]$nativeGrowthExpectedRow.file_id] = $nativeGrowthExpectedRow
        }
        $nativeGrowthServer.ConnectionContext.ExecuteNonQuery("USE [$nativeGrowthContextBefore]") | Out-Null

        foreach ($nativeGrowthRow in $nativeGrowthRows) {
            ($nativeGrowthRow.PSObject.Properties.Name -join ",") | Should -BeExactly $nativeGrowthProperties
            ($nativeGrowthRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeGrowthDisplay
            $nativeGrowthRow.PSObject.Properties["File"].MemberType | Should -Be "AliasProperty"
            $nativeGrowthRow.PSObject.Properties["FileName"].MemberType | Should -Be "AliasProperty"
            $nativeGrowthRow.File | Should -BeExactly $nativeGrowthRow.LogicalName
            $nativeGrowthRow.FileName | Should -BeExactly $nativeGrowthRow.PhysicalName
            $nativeGrowthRow.ComputerName | Should -BeExactly $nativeGrowthServer.ComputerName
            $nativeGrowthRow.InstanceName | Should -BeExactly $nativeGrowthServer.ServiceName
            $nativeGrowthRow.SqlInstance | Should -BeExactly $nativeGrowthServer.DomainInstanceName
            $nativeGrowthRow.Database | Should -BeExactly $nativeGrowthName
            $nativeGrowthRow.DatabaseID | Should -Be $nativeGrowthDatabase.ID
            $nativeGrowthRow.State | Should -BeExactly "ONLINE"
            $nativeGrowthRow.MaxSize | Should -BeOfType Dataplat.Dbatools.Utility.Size
            $nativeGrowthRow.Size | Should -BeOfType Dataplat.Dbatools.Utility.Size
            $nativeGrowthRow.UsedSpace | Should -BeOfType Dataplat.Dbatools.Utility.Size
            $nativeGrowthRow.AvailableSpace | Should -BeOfType Dataplat.Dbatools.Utility.Size
            $nativeGrowthRow.NextGrowthEventSize | Should -BeOfType Dataplat.Dbatools.Utility.Size
            $nativeGrowthRow.ReadFromDisk | Should -BeOfType Dataplat.Dbatools.Utility.Size
            $nativeGrowthRow.VolumeFreeSpace | Should -BeOfType Dataplat.Dbatools.Utility.Size
            $nativeGrowthRow.VolumeFreeSpace.Byte | Should -BeGreaterThan 0
            $nativeGrowthRow.IsOffline | Should -BeExactly "False"

            $nativeGrowthSource = $nativeGrowthExpected[[int]$nativeGrowthRow.ID]
            $nativeGrowthSource | Should -Not -BeNullOrEmpty
            $nativeGrowthRow.LogicalName | Should -BeExactly $nativeGrowthSource.name
            $nativeGrowthRow.MaxSize.Byte | Should -Be ([long]$nativeGrowthSource.max_size * 8192)
            if ($nativeGrowthSource.is_percent_growth) {
                $nativeGrowthRow.GrowthType | Should -BeExactly "Percent"
                $nativeGrowthRow.Growth | Should -Be 10
                $nativeGrowthRow.NextGrowthEventSize.Byte | Should -Be ([long][Math]::Truncate([double]$nativeGrowthSource.size * 8 * (10 * 0.01) * 1024))
            } else {
                $nativeGrowthRow.GrowthType | Should -BeExactly "kb"
                $nativeGrowthRow.Growth | Should -Be ([int]$nativeGrowthSource.growth * 8)
            }
        }

        $nativeGrowthData = $nativeGrowthRows | Where-Object LogicalName -eq $nativeGrowthName
        $nativeGrowthData.TypeDescription | Should -BeExactly "ROWS"
        $nativeGrowthData.FileGroupName | Should -BeExactly "PRIMARY"
        $nativeGrowthData.FileGroupDefault | Should -BeExactly "True"
        $nativeGrowthData.Growth | Should -Be 16384
        $nativeGrowthData.MaxSize.Byte | Should -Be 536870912
        $nativeGrowthData.NextGrowthEventSize.Byte | Should -Be 16777216

        $nativeGrowthCapped = $nativeGrowthRows | Where-Object LogicalName -eq $nativeGrowthCappedName
        $nativeGrowthCapped.FileGroupName | Should -BeExactly $nativeGrowthGroupName
        $nativeGrowthCapped.FileGroupDefault | Should -BeExactly "False"
        $nativeGrowthCapped.MaxSize.Byte | Should -Be 10485760
        $nativeGrowthCapped.NextGrowthEventSize.Byte | Should -Be 0

        $nativeGrowthLog = $nativeGrowthRows | Where-Object LogicalName -eq "$($nativeGrowthName)_log"
        $nativeGrowthLog.TypeDescription | Should -BeExactly "LOG"
        ($nativeGrowthLog.FileGroupName -is [System.DBNull]) | Should -BeTrue
        ($nativeGrowthLog.FileGroupDefault -is [System.DBNull]) | Should -BeTrue
    }

    It "reads a compatibility level 100 database without volume statistics through the fixed drive fallback" {
        $splatNativeGrowthLegacy = @{
            SqlInstance     = $nativeGrowthServer
            Database        = $nativeGrowthLegacyName
            EnableException = $true
        }
        $nativeGrowthLegacyRows = @(Get-DbaDbFileGrowth @splatNativeGrowthLegacy)
        $nativeGrowthLegacyRows.Count | Should -Be 2
        foreach ($nativeGrowthLegacyRow in $nativeGrowthLegacyRows) {
            $nativeGrowthLegacyRow.Database | Should -BeExactly $nativeGrowthLegacyName
            $nativeGrowthLegacyRow.DatabaseID | Should -Be $nativeGrowthLegacy.ID
            $nativeGrowthLegacyRow.State | Should -BeExactly "ONLINE"
            $nativeGrowthLegacyRow.VolumeFreeSpace | Should -BeOfType Dataplat.Dbatools.Utility.Size
            $nativeGrowthLegacyRow.VolumeFreeSpace.Byte | Should -BeGreaterThan 0
            ($nativeGrowthLegacyRow.VolumeFreeSpace.Byte % 1048576) | Should -Be 0
            $nativeGrowthLegacyRow.NumberOfDiskReads | Should -Not -BeNullOrEmpty
        }
    }

    It "warns per piped record when Database is given without SqlInstance, or throws with EnableException" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeGrowthGuardWarnings = @()
        $splatNativeGrowthGuard = @{
            Database        = $nativeGrowthName
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeGrowthGuardWarnings"
        }
        @(@($nativeGrowthDatabase, $nativeGrowthLegacy) | Get-DbaDbFileGrowth @splatNativeGrowthGuard).Count | Should -Be 0
        @($nativeGrowthGuardWarnings | Where-Object { "$PSItem" -like "*You must specify SqlInstance when specifying Database*" }).Count | Should -Be 2

        $nativeGrowthGuardCaught = $null
        $splatNativeGrowthGuard.EnableException = $true
        try {
            $null = Get-DbaDbFileGrowth @splatNativeGrowthGuard
        } catch {
            $nativeGrowthGuardCaught = $PSItem
        }
        $nativeGrowthGuardCaught | Should -Not -BeNullOrEmpty
        $nativeGrowthGuardCaught.Exception.Message | Should -BeExactly "You must specify SqlInstance when specifying Database"
        $nativeGrowthGuardCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbFileGrowth*"
    }

    It "continues past a failed instance with either EnableException value because discovery does not forward it" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeGrowthSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeGrowthListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeGrowthListener.Start()
            $nativeGrowthBadInstance = "127.0.0.1," + $nativeGrowthListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            foreach ($nativeGrowthFailureEnable in $false, $true) {
                $nativeGrowthFailureWarnings = @()
                $splatNativeGrowthFailure = @{
                    SqlInstance     = @($nativeGrowthServer, $nativeGrowthBadInstance, $nativeGrowthServer)
                    Database        = $nativeGrowthName
                    EnableException = $nativeGrowthFailureEnable
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "nativeGrowthFailureWarnings"
                }
                $nativeGrowthContinued = @(Get-DbaDbFileGrowth @splatNativeGrowthFailure)
                $nativeGrowthContinued.Count | Should -Be 6
                @($nativeGrowthContinued | Where-Object Database -ne $nativeGrowthName).Count | Should -Be 0
                ($nativeGrowthFailureWarnings -join " ") | Should -BeLike "*Failure*"
            }
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeGrowthSavedTimeout
            $nativeGrowthListener.Stop()
        }
    }

    It "skips a null input element with a Failure warning and still reads the rest" {
        $nativeGrowthNullWarnings = @()
        $splatNativeGrowthNull = @{
            InputObject     = @($null, $nativeGrowthDatabase)
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeGrowthNullWarnings"
        }
        $nativeGrowthNullRows = @(Get-DbaDbFileGrowth @splatNativeGrowthNull)
        $nativeGrowthNullRows.Count | Should -Be 3
        @($nativeGrowthNullRows | Where-Object Database -ne $nativeGrowthName).Count | Should -Be 0
        ($nativeGrowthNullWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "continues past a piped database that fails partway, or stops there with EnableException after earlier records" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $splatNativeGrowthPipeConnect = @{
            SqlInstance         = $TestConfig.InstanceSingle
            NonPooledConnection = $true
            EnableException     = $true
        }
        $nativeGrowthPipeServer = Connect-DbaInstance @splatNativeGrowthPipeConnect
        $nativeGrowthDropServer = Connect-DbaInstance @splatNativeGrowthPipeConnect
        try {
            $nativeGrowthPiped = @(
                $nativeGrowthPipeServer.Databases[$nativeGrowthName],
                $nativeGrowthPipeServer.Databases[$nativeGrowthDroppedName],
                $nativeGrowthPipeServer.Databases[$nativeGrowthLegacyName]
            )
            foreach ($nativeGrowthPipedDatabase in $nativeGrowthPiped) {
                $nativeGrowthPipedDatabase.IsAccessible | Should -BeTrue
            }
            $null = $nativeGrowthDropServer.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$nativeGrowthDroppedName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$nativeGrowthDroppedName];")

            $nativeGrowthPipeWarnings = @()
            $nativeGrowthPriorErrors = @($global:Error)
            $splatNativeGrowthPipe = @{
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeGrowthPipeWarnings"
            }
            $nativeGrowthPipeRows = @($nativeGrowthPiped | Get-DbaDbFileGrowth @splatNativeGrowthPipe)
            ($nativeGrowthPipeRows.Database -join ",") | Should -BeExactly (@($nativeGrowthName, $nativeGrowthName, $nativeGrowthName, $nativeGrowthLegacyName, $nativeGrowthLegacyName) -join ",")
            ($nativeGrowthPipeWarnings -join " ") | Should -BeLike "*Failure*"
            ($nativeGrowthPipeWarnings -join " ") | Should -BeLike "*$nativeGrowthDroppedName*"
            $nativeGrowthPipeError = $global:Error | Where-Object {
                $nativeGrowthPriorErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -match '^dbatools_Get-DbaDbFile(,|$)'
            } | Select-Object -First 1
            $nativeGrowthPipeError | Should -Not -BeNullOrEmpty

            $nativeGrowthEarlier = New-Object "System.Collections.Generic.List[object]"
            $nativeGrowthPipeCaught = $null
            $splatNativeGrowthPipe.EnableException = $true
            try {
                $nativeGrowthPiped | Get-DbaDbFileGrowth @splatNativeGrowthPipe | ForEach-Object { $nativeGrowthEarlier.Add($PSItem) }
            } catch {
                $nativeGrowthPipeCaught = $PSItem
            }
            $nativeGrowthEarlier.Count | Should -Be 3
            @($nativeGrowthEarlier | Where-Object Database -ne $nativeGrowthName).Count | Should -Be 0
            $nativeGrowthPipeCaught | Should -Not -BeNullOrEmpty
            $nativeGrowthPipeCaught.FullyQualifiedErrorId | Should -Match '^dbatools_Get-DbaDbFile(,|$)'
            $nativeGrowthPipeCaught.Exception.Message | Should -BeLike "*$nativeGrowthDroppedName*"
        } finally {
            $nativeGrowthPipeServer.ConnectionContext.Disconnect()
            $nativeGrowthDropServer.ConnectionContext.Disconnect()
        }
    }

    Context "Documented wildcard database selection" {
        BeforeAll {
            # Pinned help :20 documents wildcards for -Database; :119 forwards it to Get-DbaDbFile, whose
            # Get-DbaDatabase matching is literal, so the documented form never took effect.
            $nativeGrowthWildcardPrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeGrowthWildcardNames = @(
                "${nativeGrowthWildcardPrefix}_a"
                "${nativeGrowthWildcardPrefix}_b"
                "${nativeGrowthWildcardPrefix}_[a]"
            )
            $nativeGrowthWildcardCreated = New-Object System.Collections.Generic.List[string]
            foreach ($nativeGrowthWildcardName in $nativeGrowthWildcardNames) {
                $nativeGrowthWildcardDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeGrowthServer, $nativeGrowthWildcardName
                $nativeGrowthWildcardDatabase.Create()
                $nativeGrowthWildcardCreated.Add($nativeGrowthWildcardName)
            }
        }

        AfterAll {
            $nativeGrowthServer.Databases.Refresh()
            foreach ($nativeGrowthWildcardName in $nativeGrowthWildcardCreated) {
                if ($nativeGrowthServer.Databases[$nativeGrowthWildcardName]) {
                    $nativeGrowthServer.KillDatabase($nativeGrowthWildcardName)
                }
            }
        }

        It "selects databases by a documented wildcard pattern" {
            $splatNativeGrowthWildcard = @{
                SqlInstance     = $nativeGrowthServer
                Database        = "${nativeGrowthWildcardPrefix}_*"
                EnableException = $true
            }
            $nativeGrowthWildcardRows = @(Get-DbaDbFileGrowth @splatNativeGrowthWildcard)
            (($nativeGrowthWildcardRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeGrowthWildcardNames | Sort-Object) -join ",")
            $splatNativeGrowthWildcard.Database = "${nativeGrowthWildcardPrefix}_?"
            $nativeGrowthWildcardRows = @(Get-DbaDbFileGrowth @splatNativeGrowthWildcard)
            (($nativeGrowthWildcardRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeGrowthWildcardNames[0, 1] | Sort-Object) -join ",")
        }

        It "keeps bracket-only and invalid wildcard values literal" {
            $splatNativeGrowthLiteral = @{
                SqlInstance     = $nativeGrowthServer
                Database        = $nativeGrowthWildcardNames[2]
                EnableException = $true
            }
            $nativeGrowthLiteralRows = @(Get-DbaDbFileGrowth @splatNativeGrowthLiteral)
            (($nativeGrowthLiteralRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $nativeGrowthWildcardNames[2]
            $splatNativeGrowthLiteral.Database = "${nativeGrowthWildcardPrefix}_[*"
            @(Get-DbaDbFileGrowth @splatNativeGrowthLiteral).Count | Should -Be 0
        }

        # Gate-1 correction (wrong-data): pinned :119 forwards -SqlInstance to Get-DbaDbFile on every piped
        # record, and Get-DbaDbFile :270-271 appends the instance databases each time, so each instance
        # file row repeated once per piped record.
        It "reads a command-line SqlInstance once across several piped records" -Tag "NativeChecklist:pipeline-multiple" {
            $splatNativeGrowthMixed = @{
                SqlInstance     = $nativeGrowthServer
                Database        = $nativeGrowthWildcardNames[0]
                EnableException = $true
            }
            $nativeGrowthMixedRows = @(@($nativeGrowthDatabase, $nativeGrowthLegacy) | Get-DbaDbFileGrowth @splatNativeGrowthMixed)
            $nativeGrowthMixedExpected = @($nativeGrowthName, $nativeGrowthName, $nativeGrowthName, $nativeGrowthWildcardNames[0], $nativeGrowthWildcardNames[0], $nativeGrowthLegacyName, $nativeGrowthLegacyName)
            ($nativeGrowthMixedRows.Database -join ",") | Should -BeExactly ($nativeGrowthMixedExpected -join ",")
        }
    }

    Context "Real database names containing wildcard characters" {
        BeforeAll {
            # Rule E+ (pinned help :20 documents -Database wildcards): a value equal to a real database name stays
            # literal, so a caller passing a real name containing * or ? never reaches other databases.
            function New-NativeWildcardNameDatabase {
                param($Server, [string]$Name, [string]$FileStem)
                # Names with * or ? are not valid Windows file names, so the files get explicit names.
                $dataDirectory = $Server.DefaultFile
                if (-not $dataDirectory) { $dataDirectory = $Server.MasterDBPath }
                $logDirectory = $Server.DefaultLog
                if (-not $logDirectory) { $logDirectory = $Server.MasterDBLogPath }
                $separator = "\"
                if ($dataDirectory -match "/" -and $dataDirectory -notmatch "\\") { $separator = "/" }
                $database = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $Server, $Name
                $fileGroup = New-Object Microsoft.SqlServer.Management.Smo.FileGroup -ArgumentList $database, "PRIMARY"
                $database.FileGroups.Add($fileGroup)
                $dataPath = $dataDirectory.TrimEnd("\", "/") + $separator + $FileStem + ".mdf"
                $dataFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile -ArgumentList $fileGroup, ($FileStem + "_data"), $dataPath
                $dataFile.IsPrimaryFile = $true
                $fileGroup.Files.Add($dataFile)
                $logPath = $logDirectory.TrimEnd("\", "/") + $separator + $FileStem + "_log.ldf"
                $logFile = New-Object Microsoft.SqlServer.Management.Smo.LogFile -ArgumentList $database, ($FileStem + "_log"), $logPath
                $database.LogFiles.Add($logFile)
                $database.Create()
                $database
            }
            $nativeGrowthRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeGrowthRealNameNames = @("${nativeGrowthRealNamePrefix}_*", "${nativeGrowthRealNamePrefix}_?", "${nativeGrowthRealNamePrefix}_x")
            $nativeGrowthRealNameCreated = New-Object System.Collections.Generic.List[string]
            foreach ($nativeGrowthRealNameIndex in 0, 1, 2) {
                $nativeGrowthRealNameName = $nativeGrowthRealNameNames[$nativeGrowthRealNameIndex]
                $nativeGrowthRealNameDatabase = New-NativeWildcardNameDatabase -Server $nativeGrowthServer -Name $nativeGrowthRealNameName -FileStem ("${nativeGrowthRealNamePrefix}_file" + $nativeGrowthRealNameIndex)
                $nativeGrowthRealNameCreated.Add($nativeGrowthRealNameName)
            }
            $nativeGrowthServer.Databases.Refresh()
        }

        AfterAll {
            $nativeGrowthServer.Databases.Refresh()
            foreach ($nativeGrowthRealNameName in $nativeGrowthRealNameCreated) {
                if ($nativeGrowthServer.Databases[$nativeGrowthRealNameName]) {
                    $nativeGrowthServer.KillDatabase($nativeGrowthRealNameName)
                }
            }
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatNativeGrowthRealNameExact = @{
                SqlInstance     = $nativeGrowthServer
                Database        = $nativeGrowthRealNameNames[0]
                EnableException = $true
            }
            $nativeGrowthRealNameRows = @(Get-DbaDbFileGrowth @splatNativeGrowthRealNameExact)
            (($nativeGrowthRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $nativeGrowthRealNameNames[0]
            $splatNativeGrowthRealNameExact.Database = $nativeGrowthRealNameNames[1].ToUpperInvariant()
            $nativeGrowthRealNameRows = @(Get-DbaDbFileGrowth @splatNativeGrowthRealNameExact)
            (($nativeGrowthRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $nativeGrowthRealNameNames[1]
            $splatNativeGrowthRealNameExact.Database = $nativeGrowthRealNameNames[0, 1]
            $nativeGrowthRealNameRows = @(Get-DbaDbFileGrowth @splatNativeGrowthRealNameExact)
            (($nativeGrowthRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeGrowthRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatNativeGrowthRealNamePattern = @{
                SqlInstance     = $nativeGrowthServer
                Database        = "${nativeGrowthRealNamePrefix}*"
                EnableException = $true
            }
            $nativeGrowthRealNameRows = @(Get-DbaDbFileGrowth @splatNativeGrowthRealNamePattern)
            (($nativeGrowthRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeGrowthRealNameNames | Sort-Object) -join ",")
        }
    }
}

Describe "Native Get-DbaDbFileGrowth over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $sqlLoginCred = $TestConfig.SqlLoginCred
            # Unique per leg and run: the instance is shared.
            $loginDbName = "dbatoolsci_filegrowth_sqllogin_$([Guid]::NewGuid().ToString("N"))"
            $null = New-DbaDatabase -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -Name $loginDbName -EnableException
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -Database $loginDbName -Confirm:$false
        }

        It "works with -SqlCredential" {
            $loginRows = @(Get-DbaDbFileGrowth -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -Database $loginDbName -EnableException)
            $loginRows.Count | Should -Be 2
            @($loginRows | Where-Object Database -ne $loginDbName).Count | Should -Be 0
            (@($loginRows.TypeDescription | Sort-Object) -join ",") | Should -BeExactly "LOG,ROWS"
        }

        # The missing-credential assertions follow the pinned code quoted below instead of a -Baseline run, as
        # Get-DbaAgDatabase's do (watchman 49f13ebb): the base already ships the compiled Get-DbaDbFileGrowth cmdlet, and
        # the corrections this file asserts (database-wildcards, sqlinstance-read-once) fail against the pinned function.
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaDbFileGrowth.ps1:119 (every bound parameter, -EnableException too)
        #         $dbs = Get-DbaDbFile @PSBoundParameters
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaDbFile.ps1:271 (the nested call passes no -EnableException)
        #             $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaDatabase.ps1:257-262
        #         foreach ($instance in $SqlInstance) {
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        #
        # So without the credential the login fails inside Get-DbaDatabase, which warns "Failure" and returns nothing, and
        # under -EnableException it still only warns.
        It "fails cleanly without the credential: a warning and no output" {
            $noLoginWarnings = @()
            $noLoginRows = @(Get-DbaDbFileGrowth -SqlInstance $loginInstance -Database $loginDbName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue)
            $noLoginRows.Count | Should -Be 0
            ($noLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            $strictLoginWarnings = @()
            $strictLoginRows = @(Get-DbaDbFileGrowth -SqlInstance $loginInstance -Database $loginDbName -EnableException -WarningVariable strictLoginWarnings -WarningAction SilentlyContinue)
            $strictLoginRows.Count | Should -Be 0
            ($strictLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }
}

Describe "Native Get-DbaDbFileGrowth on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per test.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureDbName = $TestConfig.AzureSqlDbName
        # The database's own catalog, read directly, is what the command must report: Azure SQL Database keeps no
        # sys.master_files (Microsoft Learn, sys.master_files: SQL Server and Azure SQL Managed Instance only).
        $azureExpected = @($azureServer.Databases[$azureDbName].ExecuteWithResults("SELECT name, physical_name, max_size, growth, is_percent_growth FROM sys.database_files ORDER BY file_id;").Tables[0].Rows)
    }

    AfterAll {
        if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
    }

    It "returns the growth settings of each Azure SQL Database file from the database's own catalog" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureExpected.Count | Should -BeGreaterThan 0
        $azureWarnings = @()
        $azureRows = @(Get-DbaDbFileGrowth -SqlInstance $azureServer -Database $azureDbName -WarningVariable azureWarnings -WarningAction SilentlyContinue)
        ($azureWarnings -join " ") | Should -BeNullOrEmpty
        $azureRows.Count | Should -Be $azureExpected.Count
        foreach ($azureFile in $azureExpected) {
            $azureRow = @($azureRows | Where-Object LogicalName -eq $azureFile.name)
            $azureRow.Count | Should -Be 1
            $azureRow[0].Database | Should -BeExactly $azureDbName
            $azureRow[0].PhysicalName | Should -BeExactly $azureFile.physical_name.Trim()
            if ($azureFile.is_percent_growth) {
                $azureRow[0].GrowthType | Should -BeExactly "Percent"
                [long]$azureRow[0].Growth | Should -Be ([long]$azureFile.growth)
            } else {
                $azureRow[0].GrowthType | Should -BeExactly "kb"
                [long]$azureRow[0].Growth | Should -Be ([long]$azureFile.growth * 8)
            }
            if ([long]$azureFile.max_size -gt -1) {
                $azureRow[0].MaxSize.Byte | Should -Be ([long]$azureFile.max_size * 8192)
            } else {
                $azureRow[0].MaxSize.Byte | Should -Be -1
            }
            # Azure SQL Database exposes no volume, so the free space is unknown, not zero.
            $azureRow[0].VolumeFreeSpace | Should -BeNullOrEmpty
        }
    }

    It "returns them under -EnableException without a failure" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $strictAzureRows = @(Get-DbaDbFileGrowth -SqlInstance $azureServer -Database $azureDbName -EnableException)
        $strictAzureRows.Count | Should -Be $azureExpected.Count
        (@($strictAzureRows.LogicalName | Sort-Object) -join ",") | Should -BeExactly (@($azureExpected | ForEach-Object { $PSItem.name } | Sort-Object) -join ",")
    }
}
