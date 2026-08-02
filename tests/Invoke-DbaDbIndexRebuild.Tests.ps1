#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbIndexRebuild",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "AllDatabases",
                "AllUserDatabases",
                "Table",
                "Index",
                "Mode",
                "ReorganizeThreshold",
                "RebuildThreshold",
                "MinimumFragmentation",
                "MinimumPageCount",
                "Online",
                "MaxDop",
                "FillFactor",
                "PadIndex",
                "SortInTempdb",
                "Resumable",
                "ResumableMaxDuration",
                "WaitAtLowPriority",
                "MaxDurationMinutes",
                "AbortAfterWait",
                "IncludeHeap",
                "StatementTimeout",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeDiscovery {
        # -Skip: is read while Pester discovers the tests, long before BeforeAll runs, so the columnstore
        # decision has to be made here instead.
        $discoveryServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $columnstoreSupported = $discoveryServer.VersionMajor -ge 13
    }

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $dbName = "dbatoolsci_idxrebuild_$random"
        $msdbTableName = "dbatoolsci_idxrebuild_msdb_$random"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = New-DbaDatabase -SqlInstance $server -Name $dbName
        $testDb = Get-DbaDatabase -SqlInstance $server -Database $dbName

        $createFixtures = @"
CREATE TABLE dbo.frag1 (
    id uniqueidentifier NOT NULL CONSTRAINT PK_frag1 PRIMARY KEY CLUSTERED,
    filler char(2000) NOT NULL,
    num int NOT NULL
);
CREATE NONCLUSTERED INDEX IX_frag1_num ON dbo.frag1 (num);
CREATE TABLE dbo.heap1 (id int IDENTITY(1,1) NOT NULL, filler char(2000) NOT NULL);
CREATE TABLE dbo.heap2 (id int IDENTITY(1,1) NOT NULL, val int NOT NULL);
CREATE NONCLUSTERED INDEX IX_heap2_val ON dbo.heap2 (val);
INSERT dbo.heap2 (val) SELECT TOP 500 1 FROM sys.all_objects;
CREATE TABLE dbo.tiny1 (id int IDENTITY(1,1) NOT NULL CONSTRAINT PK_tiny1 PRIMARY KEY CLUSTERED, val int NOT NULL);
INSERT dbo.tiny1 (val) SELECT TOP 10 1 FROM sys.all_objects;
CREATE TABLE dbo.calc1 (
    id int NOT NULL CONSTRAINT PK_calc1 PRIMARY KEY CLUSTERED,
    num int NOT NULL,
    doubled AS (num * 2) PERSISTED
);
CREATE NONCLUSTERED INDEX IX_calc1_doubled ON dbo.calc1 (doubled);
INSERT dbo.calc1 (id, num) SELECT TOP 200 ROW_NUMBER() OVER (ORDER BY name), 1 FROM sys.all_objects;
CREATE TABLE dbo.nopage1 (id int NOT NULL CONSTRAINT PK_nopage1 PRIMARY KEY CLUSTERED, val int NOT NULL);
INSERT dbo.nopage1 (id, val) SELECT TOP 200 ROW_NUMBER() OVER (ORDER BY name), 1 FROM sys.all_objects;
CREATE NONCLUSTERED INDEX IX_nopage1_val ON dbo.nopage1 (val) WITH (ALLOW_PAGE_LOCKS = OFF);
CREATE TABLE dbo.filtered1 (id int NOT NULL CONSTRAINT PK_filtered1 PRIMARY KEY CLUSTERED, val int NOT NULL);
INSERT dbo.filtered1 (id, val) SELECT TOP 200 ROW_NUMBER() OVER (ORDER BY name), 1 FROM sys.all_objects;
CREATE NONCLUSTERED INDEX IX_filtered1_val ON dbo.filtered1 (val) WHERE val > 0;
SET NOCOUNT ON;
DECLARE @i int = 0;
WHILE @i < 3000 BEGIN
    INSERT dbo.heap1 (filler) VALUES ('x');
    SET @i += 1;
END
DELETE FROM dbo.heap1 WHERE id % 3 = 0;
"@

        # Inserted row by row on purpose: the GUID keys then arrive out of order and the clustered index really fragments.
        $fragmentFrag1 = @"
TRUNCATE TABLE dbo.frag1;
SET NOCOUNT ON;
DECLARE @i int = 0;
WHILE @i < 3000 BEGIN
    INSERT dbo.frag1 (id, filler, num) VALUES (NEWID(), 'x', @i);
    SET @i += 1;
END
"@

        $measureFrag1 = @"
SELECT AVG(s.avg_fragmentation_in_percent) AS AvgFragmentation
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.frag1'), 1, NULL, 'LIMITED') AS s
"@

        $measureFillFactor = @"
SELECT fill_factor
FROM sys.indexes
WHERE object_id = OBJECT_ID('dbo.frag1') AND name = 'IX_frag1_num'
"@

        $testDb.Query($createFixtures)
        $testDb.Query($fragmentFrag1)

        # Columnstore is SQL Server 2016 and later on every edition. Older instances get no columnstore fixture
        # and the columnstore context skips itself.
        $supportsColumnstore = $server.VersionMajor -ge 13
        if ($supportsColumnstore) {
            $createColumnstore = @"
CREATE TABLE dbo.cs1 (id int NOT NULL, val int NOT NULL);
INSERT dbo.cs1 (id, val) SELECT TOP 500 1, 1 FROM sys.all_objects;
CREATE CLUSTERED COLUMNSTORE INDEX CCI_cs1 ON dbo.cs1;
"@
            $testDb.Query($createColumnstore)
        }

        # A user table in msdb is the only way to tell -AllDatabases from -AllUserDatabases, because
        # every table msdb ships with is a system object and is skipped.
        $msdbDb = Get-DbaDatabase -SqlInstance $server -Database msdb
        $createMsdbTable = @"
CREATE TABLE dbo.$msdbTableName (
    id int IDENTITY(1,1) NOT NULL CONSTRAINT PK_$msdbTableName PRIMARY KEY CLUSTERED,
    val int NOT NULL
);
INSERT dbo.$msdbTableName (val) SELECT TOP 100 1 FROM sys.all_objects;
"@
        $msdbDb.Query($createMsdbTable)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # The msdb table has to be dropped whatever happened to it, or the database still goes even if it is already gone.
        try {
            $msdbDb.Query("DROP TABLE IF EXISTS dbo.$msdbTableName")
        } catch {
            Write-Warning "Could not drop dbo.$msdbTableName from msdb. $PSItem"
        }
        $splatCleanup = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $dbName
            Confirm     = $false
            ErrorAction = "SilentlyContinue"
        }
        $null = Remove-DbaDatabase @splatCleanup

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Rebuilding a named index" {
        BeforeAll {
            $testDb.Query($fragmentFrag1)
            $splatRebuild = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Table       = "dbo.frag1"
                Index       = "PK_frag1"
            }
            $rebuildResult = Invoke-DbaDbIndexRebuild @splatRebuild
        }

        It "Returns one row for the requested index" {
            $rebuildResult.IndexName | Should -Be "PK_frag1"
            $rebuildResult.IndexType | Should -Be "ClusteredIndex"
        }

        It "Reports the operation it performed" {
            $rebuildResult.Operation | Should -Be "Rebuild"
            $rebuildResult.Success | Should -Be $true
        }

        It "Leaves the index less fragmented than it found it" {
            $rebuildResult.FragmentationBefore | Should -BeGreaterThan 30
            $rebuildResult.FragmentationAfter | Should -BeLessThan $rebuildResult.FragmentationBefore
        }
    }

    Context "Reorganizing" {
        BeforeAll {
            $testDb.Query($fragmentFrag1)
            $splatReorganize = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Table       = "dbo.frag1"
                Index       = "PK_frag1"
                Mode        = "Reorganize"
            }
            $reorganizeResult = Invoke-DbaDbIndexRebuild @splatReorganize
        }

        It "Reports a reorganize rather than a rebuild" {
            $reorganizeResult.Operation | Should -Be "Reorganize"
            $reorganizeResult.Success | Should -Be $true
        }

        It "Reports the reorganize as online, because REORGANIZE always is" {
            $reorganizeResult.Online | Should -Be $true
        }

        It "Skips an index that has page level locking disabled" {
            $splatNoPageLocks = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                Table           = "dbo.nopage1"
                Index           = "IX_nopage1_val"
                Mode            = "Reorganize"
                WarningVariable = "noPageLockWarning"
                WarningAction   = "SilentlyContinue"
            }
            $noPageLocks = Invoke-DbaDbIndexRebuild @splatNoPageLocks
            $noPageLocks | Should -BeNullOrEmpty
            $noPageLockWarning | Should -Match "ALLOW_PAGE_LOCKS"
        }

        It "Warns about rebuild only options rather than refusing to reorganize" {
            $splatIgnoredOptions = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                Table           = "dbo.frag1"
                Index           = "PK_frag1"
                Mode            = "Reorganize"
                Resumable       = $true
                WarningVariable = "ignoredWarning"
                WarningAction   = "SilentlyContinue"
            }
            $ignoredOptions = Invoke-DbaDbIndexRebuild @splatIgnoredOptions
            $ignoredOptions.Operation | Should -Be "Reorganize"
            $ignoredOptions.Success | Should -Be $true
            $ignoredWarning | Should -Match "REORGANIZE ignores these options"
        }
    }

    Context "Auto mode picks the operation from measured fragmentation" {
        BeforeEach {
            $testDb.Query($fragmentFrag1)
        }

        It "Rebuilds when fragmentation is at or above RebuildThreshold" {
            $splatAutoRebuild = @{
                SqlInstance      = $TestConfig.InstanceSingle
                Database         = $dbName
                Table            = "dbo.frag1"
                Index            = "PK_frag1"
                Mode             = "Auto"
                RebuildThreshold = 30
            }
            $autoRebuild = Invoke-DbaDbIndexRebuild @splatAutoRebuild
            $autoRebuild.Operation | Should -Be "Rebuild"
        }

        It "Reorganizes when fragmentation sits between the two thresholds" {
            $splatAutoReorganize = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Database            = $dbName
                Table               = "dbo.frag1"
                Index               = "PK_frag1"
                Mode                = "Auto"
                ReorganizeThreshold = 1
                RebuildThreshold    = 100
            }
            $autoReorganize = Invoke-DbaDbIndexRebuild @splatAutoReorganize
            $autoReorganize.Operation | Should -Be "Reorganize"
        }

        It "Skips anything below ReorganizeThreshold" {
            $splatAutoSkip = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Database            = $dbName
                Table               = "dbo.frag1"
                Index               = "PK_frag1"
                Mode                = "Auto"
                ReorganizeThreshold = 100
                RebuildThreshold    = 100
                WarningVariable     = "autoSkipWarning"
                WarningAction       = "SilentlyContinue"
            }
            $autoSkip = Invoke-DbaDbIndexRebuild @splatAutoSkip
            $autoSkip | Should -BeNullOrEmpty
            $autoSkipWarning | Should -BeNullOrEmpty
        }

        It "Refuses thresholds that are the wrong way round" {
            $splatBadThresholds = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Database            = $dbName
                Mode                = "Auto"
                ReorganizeThreshold = 60
                RebuildThreshold    = 30
                WarningVariable     = "thresholdWarning"
                WarningAction       = "SilentlyContinue"
            }
            $badThresholds = Invoke-DbaDbIndexRebuild @splatBadThresholds
            $badThresholds | Should -BeNullOrEmpty
            $thresholdWarning | Should -Match "cannot be greater than RebuildThreshold"
        }
    }

    Context "Heaps" {
        It "Rebuilds a heap when IncludeHeap is used" {
            $splatHeap = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Table       = "dbo.heap1"
                IncludeHeap = $true
            }
            $heapResult = Invoke-DbaDbIndexRebuild @splatHeap
            $heapResult.IndexType | Should -Be "Heap"
            $heapResult.IndexName | Should -Be "heap1"
            $heapResult.Operation | Should -Be "Rebuild"
            $heapResult.Success | Should -Be $true
        }

        It "Leaves heaps alone by default" {
            $defaultResult = Invoke-DbaDbIndexRebuild -SqlInstance $TestConfig.InstanceSingle -Database $dbName
            $defaultResult.IndexType | Should -Not -Contain "Heap"
        }

        It "Warns rather than failing when asked to reorganize a heap" {
            $splatHeapReorganize = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                Table           = "dbo.heap1"
                IncludeHeap     = $true
                Mode            = "Reorganize"
                WarningVariable = "heapWarning"
                WarningAction   = "SilentlyContinue"
            }
            $heapReorganize = Invoke-DbaDbIndexRebuild @splatHeapReorganize
            $heapReorganize | Should -BeNullOrEmpty
            $heapWarning | Should -Match "cannot be reorganized"
        }

        It "Does not rebuild a nonclustered index the heap rebuild already covered" {
            $splatHeapWithIndex = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Table       = "dbo.heap2"
                IncludeHeap = $true
            }
            $heapWithIndex = Invoke-DbaDbIndexRebuild @splatHeapWithIndex
            $heapWithIndex.IndexName | Should -Be "heap2"
            $heapWithIndex.IndexName | Should -Not -Contain "IX_heap2_val"
        }

        It "Does not decide Auto mode from fragmentation the heap rebuild already invalidated" {
            $splatHeapAuto = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Database            = $dbName
                Table               = "dbo.heap2"
                IncludeHeap         = $true
                Mode                = "Auto"
                ReorganizeThreshold = 0
                RebuildThreshold    = 0
            }
            $heapAuto = Invoke-DbaDbIndexRebuild @splatHeapAuto
            $heapAuto.IndexName | Should -Be "heap2"
            $heapAuto.IndexName | Should -Not -Contain "IX_heap2_val"
        }
    }

    Context "Columnstore" -Skip:(-not $columnstoreSupported) {
        It "Rebuilds a columnstore index without pretending to measure it" {
            $splatColumnstore = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Table       = "dbo.cs1"
            }
            $columnstoreResult = Invoke-DbaDbIndexRebuild @splatColumnstore
            $columnstoreResult.IndexType | Should -Be "ClusteredColumnStoreIndex"
            $columnstoreResult.Success | Should -Be $true
            $columnstoreResult.PageCount | Should -BeNullOrEmpty
            $columnstoreResult.FragmentationBefore | Should -BeNullOrEmpty
        }

        It "Skips a columnstore index in Auto mode and says why" {
            $splatColumnstoreAuto = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                Table           = "dbo.cs1"
                Mode            = "Auto"
                WarningVariable = "columnstoreWarning"
                WarningAction   = "SilentlyContinue"
            }
            $columnstoreAuto = Invoke-DbaDbIndexRebuild @splatColumnstoreAuto
            $columnstoreAuto | Should -BeNullOrEmpty
            $columnstoreWarning | Should -Match "cannot be measured"
        }
    }

    Context "Filters" {
        It "Returns nothing when every index is below MinimumPageCount" {
            $splatPageFilter = @{
                SqlInstance      = $TestConfig.InstanceSingle
                Database         = $dbName
                MinimumPageCount = 100000
                WarningAction    = "SilentlyContinue"
            }
            $pageFiltered = Invoke-DbaDbIndexRebuild @splatPageFilter
            $pageFiltered | Should -BeNullOrEmpty
        }

        It "Returns nothing when every index is below MinimumFragmentation" {
            $splatFragFilter = @{
                SqlInstance          = $TestConfig.InstanceSingle
                Database             = $dbName
                MinimumFragmentation = 100
                WarningAction        = "SilentlyContinue"
            }
            $fragFiltered = Invoke-DbaDbIndexRebuild @splatFragFilter
            $fragFiltered | Should -BeNullOrEmpty
        }
    }

    Context "Database selection" {
        It "Warns when no database was specified" {
            $splatNoSelector = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "selectorWarning"
                WarningAction   = "SilentlyContinue"
            }
            $noSelector = Invoke-DbaDbIndexRebuild @splatNoSelector
            $noSelector | Should -BeNullOrEmpty
            $selectorWarning | Should -Match "You must specify databases"
        }

        It "Reaches system databases with AllDatabases" {
            $splatAllDatabases = @{
                SqlInstance   = $TestConfig.InstanceSingle
                AllDatabases  = $true
                Table         = "dbo.$msdbTableName"
                WarningAction = "SilentlyContinue"
            }
            $allDatabases = Invoke-DbaDbIndexRebuild @splatAllDatabases
            $allDatabases.Database | Should -Contain "msdb"
        }

        It "Leaves system databases alone with AllUserDatabases" {
            $splatAllUserDatabases = @{
                SqlInstance      = $TestConfig.InstanceSingle
                AllUserDatabases = $true
                Table            = "dbo.$msdbTableName"
                WarningAction    = "SilentlyContinue"
            }
            $allUserDatabases = Invoke-DbaDbIndexRebuild @splatAllUserDatabases
            $allUserDatabases | Should -BeNullOrEmpty
        }

        It "Warns when there is neither an instance nor pipeline input" {
            $splatNoInstance = @{
                Database        = $dbName
                WarningVariable = "instanceWarning"
                WarningAction   = "SilentlyContinue"
            }
            $noInstance = Invoke-DbaDbIndexRebuild @splatNoInstance
            $noInstance | Should -BeNullOrEmpty
            $instanceWarning | Should -Match "You must specify -SqlInstance"
        }

        It "Applies ExcludeDatabase to piped databases" {
            $excludedPipe = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName | Invoke-DbaDbIndexRebuild -ExcludeDatabase $dbName
            $excludedPipe | Should -BeNullOrEmpty
        }
    }

    Context "Read only databases" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $readOnlyDbName = "dbatoolsci_idxrebuild_ro_$random"
            $null = New-DbaDatabase -SqlInstance $server -Name $readOnlyDbName
            $readOnlyDb = Get-DbaDatabase -SqlInstance $server -Database $readOnlyDbName
            $readOnlyDb.Query("CREATE TABLE dbo.ro1 (id int NOT NULL CONSTRAINT PK_ro1 PRIMARY KEY CLUSTERED);")
            $splatMakeReadOnly = @{
                SqlInstance = $server
                Database    = $readOnlyDbName
                ReadOnly    = $true
                Force       = $true
            }
            $null = Set-DbaDbState @splatMakeReadOnly
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $splatMakeWritable = @{
                SqlInstance = $server
                Database    = $readOnlyDbName
                ReadWrite   = $true
                Force       = $true
                ErrorAction = "SilentlyContinue"
            }
            $null = Set-DbaDbState @splatMakeWritable
            $splatReadOnlyCleanup = @{
                SqlInstance = $server
                Database    = $readOnlyDbName
                Confirm     = $false
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaDatabase @splatReadOnlyCleanup
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Skips the database once rather than failing once per index" {
            $splatReadOnly = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $readOnlyDbName
                WarningVariable = "readOnlyWarning"
                WarningAction   = "SilentlyContinue"
            }
            $readOnlyResult = Invoke-DbaDbIndexRebuild @splatReadOnly
            $readOnlyResult | Should -BeNullOrEmpty
            $readOnlyWarning | Should -Match "is read only"
        }
    }

    Context "WhatIf" {
        BeforeAll {
            $testDb.Query($fragmentFrag1)
            $fragmentationBeforeWhatIf = ($testDb.Query($measureFrag1)).AvgFragmentation
            $splatWhatIf = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                WhatIf      = $true
            }
            $whatIfResult = Invoke-DbaDbIndexRebuild @splatWhatIf
            $fragmentationAfterWhatIf = ($testDb.Query($measureFrag1)).AvgFragmentation
        }

        It "Returns nothing" {
            $whatIfResult | Should -BeNullOrEmpty
        }

        It "Does not touch the index" {
            $fragmentationAfterWhatIf | Should -Be $fragmentationBeforeWhatIf
        }
    }

    Context "Pipeline input" {
        It "Accepts databases from Get-DbaDatabase" {
            $pipedDatabase = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName | Invoke-DbaDbIndexRebuild
            $pipedDatabase.Database | Should -Contain $dbName
            $pipedDatabase.Success | Should -Not -Contain $false
        }

        It "Accepts tables from Get-DbaDbTable" {
            $splatPipedTable = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Table       = "dbo.frag1"
            }
            $pipedTable = Get-DbaDbTable @splatPipedTable | Invoke-DbaDbIndexRebuild
            $pipedTable.Table | Should -Not -Contain "tiny1"
            ($pipedTable.IndexName | Sort-Object) | Should -Be @("IX_frag1_num", "PK_frag1")
        }

        It "Warns about input it cannot use" {
            $badInput = "not an smo object" | Invoke-DbaDbIndexRebuild -WarningVariable inputWarning -WarningAction SilentlyContinue
            $badInput | Should -BeNullOrEmpty
            $inputWarning | Should -Match "is not supported"
        }
    }

    Context "Index options" {
        It "Applies FillFactor to the rebuilt index" {
            $splatFillFactor = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Table       = "dbo.frag1"
                Index       = "IX_frag1_num"
                FillFactor  = 70
            }
            $null = Invoke-DbaDbIndexRebuild @splatFillFactor
            $fillFactorRow = $testDb.Query($measureFillFactor)
            $fillFactorRow.fill_factor | Should -Be 70
        }

        It "Rebuilds online" {
            # Set-ItResult marks the result but does not stop the block, so the rest has to be skipped explicitly.
            if ($server.EngineEdition -ne "EnterpriseOrDeveloper") {
                Set-ItResult -Skipped -Because "online index rebuilds require Enterprise or Developer edition"
                return
            }
            $splatOnline = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Table       = "dbo.frag1"
                Index       = "PK_frag1"
                Online      = $true
            }
            $onlineResult = Invoke-DbaDbIndexRebuild @splatOnline
            $onlineResult.Online | Should -Be $true
            $onlineResult.Success | Should -Be $true
        }

        It "Rebuilds as a resumable online operation" {
            if ($server.EngineEdition -ne "EnterpriseOrDeveloper") {
                Set-ItResult -Skipped -Because "resumable index rebuilds require Enterprise or Developer edition"
                return
            }
            if ($server.VersionMajor -lt 14) {
                Set-ItResult -Skipped -Because "resumable index rebuilds require SQL Server 2017 or later"
                return
            }
            $splatResumable = @{
                SqlInstance          = $TestConfig.InstanceSingle
                Database             = $dbName
                Table                = "dbo.frag1"
                Index                = "PK_frag1"
                Online               = $true
                Resumable            = $true
                ResumableMaxDuration = 5
            }
            $resumableResult = Invoke-DbaDbIndexRebuild @splatResumable
            $resumableResult.Resumable | Should -Be $true
            $resumableResult.Success | Should -Be $true
        }

        It "Suppresses resumable on a filtered index" {
            if ($server.EngineEdition -ne "EnterpriseOrDeveloper") {
                Set-ItResult -Skipped -Because "resumable index rebuilds require Enterprise or Developer edition"
                return
            }
            if ($server.VersionMajor -lt 14) {
                Set-ItResult -Skipped -Because "resumable index rebuilds require SQL Server 2017 or later"
                return
            }
            $splatFilteredResumable = @{
                SqlInstance          = $TestConfig.InstanceSingle
                Database             = $dbName
                Table                = "dbo.filtered1"
                Index                = "IX_filtered1_val"
                Online               = $true
                Resumable            = $true
                ResumableMaxDuration = 5
            }
            $filteredResumable = Invoke-DbaDbIndexRebuild @splatFilteredResumable
            $filteredResumable.Resumable | Should -Be $false
            $filteredResumable.Success | Should -Be $true
            $filteredResumable.Notes | Should -Match "filtered index"
        }

        It "Suppresses resumable on an index whose key column is computed" {
            if ($server.EngineEdition -ne "EnterpriseOrDeveloper") {
                Set-ItResult -Skipped -Because "resumable index rebuilds require Enterprise or Developer edition"
                return
            }
            if ($server.VersionMajor -lt 14) {
                Set-ItResult -Skipped -Because "resumable index rebuilds require SQL Server 2017 or later"
                return
            }
            $splatComputedResumable = @{
                SqlInstance          = $TestConfig.InstanceSingle
                Database             = $dbName
                Table                = "dbo.calc1"
                Index                = "IX_calc1_doubled"
                Online               = $true
                Resumable            = $true
                ResumableMaxDuration = 5
            }
            $computedResumable = Invoke-DbaDbIndexRebuild @splatComputedResumable
            $computedResumable.Resumable | Should -Be $false
            $computedResumable.Success | Should -Be $true
        }

        It "Refuses a resumable duration above the seven day ceiling" {
            $splatOverCeiling = @{
                SqlInstance          = $TestConfig.InstanceSingle
                Database             = $dbName
                Online               = $true
                Resumable            = $true
                ResumableMaxDuration = 10081
            }
            { Invoke-DbaDbIndexRebuild @splatOverCeiling } | Should -Throw
        }

        It "Refuses a resumable rebuild that is not online" {
            $splatBadResumable = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                Resumable       = $true
                WarningVariable = "resumableWarning"
                WarningAction   = "SilentlyContinue"
            }
            $badResumable = Invoke-DbaDbIndexRebuild @splatBadResumable
            $badResumable | Should -BeNullOrEmpty
            $resumableWarning | Should -Match "requires ONLINE"
        }

        It "Refuses WaitAtLowPriority that is not online" {
            $splatBadWait = @{
                SqlInstance       = $TestConfig.InstanceSingle
                Database          = $dbName
                WaitAtLowPriority = $true
                WarningVariable   = "waitWarning"
                WarningAction     = "SilentlyContinue"
            }
            $badWait = Invoke-DbaDbIndexRebuild @splatBadWait
            $badWait | Should -BeNullOrEmpty
            $waitWarning | Should -Match "WAIT_AT_LOW_PRIORITY"
        }

        It "Refuses SortInTempdb combined with Resumable" {
            $splatBadSort = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                Online          = $true
                Resumable       = $true
                SortInTempdb    = $true
                WarningVariable = "sortWarning"
                WarningAction   = "SilentlyContinue"
            }
            $badSort = Invoke-DbaDbIndexRebuild @splatBadSort
            $badSort | Should -BeNullOrEmpty
            $sortWarning | Should -Match "SORT_IN_TEMPDB"
        }

        It "Refuses AbortAfterWait without something to wait for" {
            $splatBadAbort = @{
                SqlInstance       = $TestConfig.InstanceSingle
                Database          = $dbName
                Online            = $true
                WaitAtLowPriority = $true
                AbortAfterWait    = "Blockers"
                WarningVariable   = "abortWarning"
                WarningAction     = "SilentlyContinue"
            }
            $badAbort = Invoke-DbaDbIndexRebuild @splatBadAbort
            $badAbort | Should -BeNullOrEmpty
            $abortWarning | Should -Match "MaxDurationMinutes"
        }

        It "Refuses AbortAfterWait without WaitAtLowPriority" {
            $splatLonelyAbort = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                AbortAfterWait  = "Blockers"
                WarningVariable = "lonelyAbortWarning"
                WarningAction   = "SilentlyContinue"
            }
            $lonelyAbort = Invoke-DbaDbIndexRebuild @splatLonelyAbort
            $lonelyAbort | Should -BeNullOrEmpty
            $lonelyAbortWarning | Should -Match "WaitAtLowPriority"
        }
    }
}
