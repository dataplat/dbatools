#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaReplArticleColumn",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads publication articles and their columns.
# NativeChecklist: azure-sqldb N/A -- Azure SQL Database can only be a push subscriber; it cannot be a publisher, so it holds no publications or articles: https://learn.microsoft.com/azure/azure-sql/database/replication-to-sql-database; the nested Get-DbaReplArticle refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

Describe "Native Get-DbaReplArticleColumn" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        # Unique names per run, so legs never touch each other's objects.
        $suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $dbName = "dbatoolsci_replcol_$suffix"
        $transPubName = "dbatoolsci_ctpub_$suffix"
        $mergePubName = "dbatoolsci_cmpub_$suffix"
        $vpDbName = "dbatoolsci_replvp_$suffix"
        $vpPubOne = "dbatoolsci_vp1_$suffix"
        $vpPubTwo = "dbatoolsci_vp2_$suffix"
        $vpMergePubName = "dbatoolsci_vpm_$suffix"
        $badInstance = "Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False"
        $expectedView = @("ComputerName", "InstanceName", "SqlInstance", "DatabaseName", "PublicationName", "ArticleName", "ArticleId", "ColumnName")

        # Makes the instance its own distributor and local publisher through RMO, as Microsoft Learn's
        # ReplicationDatabase example does. It refuses an instance that already has replication configured.
        $fixtureServer = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        $replication = New-Object Microsoft.SqlServer.Replication.ReplicationServer -ArgumentList $fixtureServer.ConnectionContext
        if ($replication.IsDistributor -or $replication.IsPublisher -or [int]$fixtureServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.servers WHERE is_distributor = 1") -ne 0) {
            throw "Native article column fixture requires an instance without existing distribution or publishing; existing configuration was not changed."
        }
        $distributionName = "native_distribution_$suffix"
        $publisherName = [string]$fixtureServer.ConnectionContext.ExecuteScalar("SELECT @@SERVERNAME")
        $fixtureBuilt = $true

        $distributionDatabase = New-Object Microsoft.SqlServer.Replication.DistributionDatabase -ArgumentList $distributionName, $fixtureServer.ConnectionContext
        $replication.InstallDistributor([string]$null, $distributionDatabase)
        $publisher = New-Object Microsoft.SqlServer.Replication.DistributionPublisher -ArgumentList $publisherName, $fixtureServer.ConnectionContext
        $publisher.DistributionDatabase = $distributionName
        # A path on the server: Join-Path would resolve its drive on the test host instead.
        $publisher.WorkingDirectory = $fixtureServer.InstallDataDirectory.TrimEnd("\") + "\ReplData"
        $publisher.PublisherSecurity.WindowsAuthentication = $true
        $publisher.Create()

        # Two transactional articles, one of them vertically partitioned, and one merge article.
        $null = $fixtureServer.ConnectionContext.ExecuteNonQuery("CREATE DATABASE [$dbName]")
        $fixtureServer.Databases.Refresh()
        $fixtureDb = $fixtureServer.Databases[$dbName]
        $null = $fixtureDb.ExecuteNonQuery("CREATE SCHEMA colsales")
        $null = $fixtureDb.ExecuteNonQuery("CREATE TABLE dbo.ColAlpha (Id int NOT NULL PRIMARY KEY, Val nvarchar(20) NULL, Extra int NULL)")
        $null = $fixtureDb.ExecuteNonQuery("CREATE TABLE colsales.ColBeta (Id int NOT NULL PRIMARY KEY, Val nvarchar(20) NULL, Secret int NULL, Tail int NULL)")
        $null = $fixtureDb.ExecuteNonQuery("CREATE TABLE dbo.ColGamma (Id int NOT NULL PRIMARY KEY, Val nvarchar(20) NULL)")

        $publicationDb = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase -ArgumentList $dbName, $fixtureServer.ConnectionContext
        $publicationDb.LoadProperties() | Should -BeTrue
        # The order New-DbaReplPublication uses: enable, commit, then the log reader agent transactional publishing needs.
        $publicationDb.EnabledTransPublishing = $true
        $publicationDb.CommitPropertyChanges()
        if (-not $publicationDb.LogReaderAgentExists) {
            $publicationDb.CreateLogReaderAgent()
        }
        $publicationDb.EnabledMergePublishing = $true
        $publicationDb.CommitPropertyChanges()

        $transPub = New-Object Microsoft.SqlServer.Replication.TransPublication
        $transPub.ConnectionContext = $fixtureServer.ConnectionContext
        $transPub.DatabaseName = $dbName
        $transPub.Name = $transPubName
        $transPub.Type = [Microsoft.SqlServer.Replication.PublicationType]::Transactional
        $transPub.Create()
        foreach ($source in @(@("ColAlpha", "dbo"), @("ColBeta", "colsales"))) {
            $article = New-Object Microsoft.SqlServer.Replication.TransArticle
            $article.ConnectionContext = $fixtureServer.ConnectionContext
            $article.Name = $source[0]
            $article.DatabaseName = $dbName
            $article.SourceObjectName = $source[0]
            $article.SourceObjectOwner = $source[1]
            $article.PublicationName = $transPubName
            $article.Type = [Microsoft.SqlServer.Replication.ArticleOptions]::LogBased
            $article.Create()
            if ($source[0] -eq "ColBeta") {
                # Microsoft Learn's TransArticle example: removing a column makes the article vertically partitioned.
                $article.RemoveReplicatedColumns([string[]]@("Secret"))
            }
        }

        $mergePub = New-Object Microsoft.SqlServer.Replication.MergePublication
        $mergePub.ConnectionContext = $fixtureServer.ConnectionContext
        $mergePub.DatabaseName = $dbName
        $mergePub.Name = $mergePubName
        $mergePub.Create()
        $mergeArticle = New-Object Microsoft.SqlServer.Replication.MergeArticle
        $mergeArticle.ConnectionContext = $fixtureServer.ConnectionContext
        $mergeArticle.Name = "ColGamma"
        $mergeArticle.DatabaseName = $dbName
        $mergeArticle.SourceObjectName = "ColGamma"
        $mergeArticle.SourceObjectOwner = "dbo"
        $mergeArticle.PublicationName = $mergePubName
        $mergeArticle.Type = [Microsoft.SqlServer.Replication.ArticleOptions]::TableBased
        $mergeArticle.Create()

        # Every column each source table has now, in column order: merge publishing adds its rowguid column to ColGamma.
        $tableColumns = @{}
        foreach ($table in @(@("ColAlpha", "dbo"), @("ColBeta", "colsales"), @("ColGamma", "dbo"))) {
            $names = $fixtureDb.ExecuteWithResults("SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID(N'$($table[1]).$($table[0])') ORDER BY c.column_id").Tables[0].Rows | ForEach-Object { $PSItem[0] }
            $tableColumns[$table[0]] = @($names)
        }

        # A second database for the vertical-partition corrections: one article name, DupArt over dbo.DupT, in two
        # transactional publications, each partitioned differently, and a vertically partitioned merge article.
        $null = $fixtureServer.ConnectionContext.ExecuteNonQuery("CREATE DATABASE [$vpDbName]")
        $fixtureServer.Databases.Refresh()
        $vpDb = $fixtureServer.Databases[$vpDbName]
        $null = $vpDb.ExecuteNonQuery("CREATE TABLE dbo.DupT (Id int NOT NULL PRIMARY KEY, A int NULL, B int NULL, C int NULL)")
        $null = $vpDb.ExecuteNonQuery("CREATE TABLE dbo.MergeT (Id int NOT NULL PRIMARY KEY, A int NULL, B int NULL)")
        $vpPublicationDb = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase -ArgumentList $vpDbName, $fixtureServer.ConnectionContext
        $vpPublicationDb.LoadProperties() | Should -BeTrue
        $vpPublicationDb.EnabledTransPublishing = $true
        $vpPublicationDb.CommitPropertyChanges()
        if (-not $vpPublicationDb.LogReaderAgentExists) {
            $vpPublicationDb.CreateLogReaderAgent()
        }
        $vpPublicationDb.EnabledMergePublishing = $true
        $vpPublicationDb.CommitPropertyChanges()
        foreach ($pair in @(@($vpPubOne, "C"), @($vpPubTwo, "B"))) {
            $vpPub = New-Object Microsoft.SqlServer.Replication.TransPublication
            $vpPub.ConnectionContext = $fixtureServer.ConnectionContext
            $vpPub.DatabaseName = $vpDbName
            $vpPub.Name = $pair[0]
            $vpPub.Type = [Microsoft.SqlServer.Replication.PublicationType]::Transactional
            $vpPub.Create()
            $vpArticle = New-Object Microsoft.SqlServer.Replication.TransArticle
            $vpArticle.ConnectionContext = $fixtureServer.ConnectionContext
            $vpArticle.Name = "DupArt"
            $vpArticle.DatabaseName = $vpDbName
            $vpArticle.SourceObjectName = "DupT"
            $vpArticle.SourceObjectOwner = "dbo"
            $vpArticle.PublicationName = $pair[0]
            $vpArticle.Type = [Microsoft.SqlServer.Replication.ArticleOptions]::LogBased
            $vpArticle.Create()
            $vpArticle.RemoveReplicatedColumns([string[]]@($pair[1]))
        }
        $vpMerge = New-Object Microsoft.SqlServer.Replication.MergePublication
        $vpMerge.ConnectionContext = $fixtureServer.ConnectionContext
        $vpMerge.DatabaseName = $vpDbName
        $vpMerge.Name = $vpMergePubName
        $vpMerge.Create()
        $vpMergeArticle = New-Object Microsoft.SqlServer.Replication.MergeArticle
        $vpMergeArticle.ConnectionContext = $fixtureServer.ConnectionContext
        $vpMergeArticle.Name = "MergeT"
        $vpMergeArticle.DatabaseName = $vpDbName
        $vpMergeArticle.SourceObjectName = "MergeT"
        $vpMergeArticle.SourceObjectOwner = "dbo"
        $vpMergeArticle.PublicationName = $vpMergePubName
        $vpMergeArticle.Type = [Microsoft.SqlServer.Replication.ArticleOptions]::TableBased
        $vpMergeArticle.Create()
        $vpMergeArticle.RemoveReplicatedColumns([string[]]@("B"))
        # MergeT's columns now, in column order (merge publishing adds its rowguid column), less the one the article drops.
        $mergeTColumns = @($vpDb.ExecuteWithResults("SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID(N'dbo.MergeT') ORDER BY c.column_id").Tables[0].Rows | ForEach-Object { $PSItem[0] })
        $vpMergeColumns = @($mergeTColumns | Where-Object { $PSItem -ne "B" })
    }


    AfterAll {
        if (-not $fixtureBuilt) { return }
        # The fixture connection sits in the published database after its ExecuteNonQuery calls; close it first.
        $fixtureServer.ConnectionContext.Disconnect()
        # A fresh connection, so cleanup never depends on the state the command left its own connection in.
        $cleanup = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        # Each step runs even when an earlier one fails; the database is dropped last, after the distributor (and the
        # agent jobs it owns) is gone, with a few attempts, so nothing still holding it can stop the drop.
        $cleanupFailures = @()
        foreach ($cleanupName in $dbName, $vpDbName) {
            $cleanupDb = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase -ArgumentList $cleanupName, $cleanup.ConnectionContext
            $cleanupLoaded = $false
            try { $cleanupLoaded = $cleanupDb.LoadProperties() } catch { $cleanupFailures += $PSItem }
            $cleanupPublications = @()
            if ($cleanupLoaded) {
                try { $cleanupPublications = @($cleanupDb.TransPublications) + @($cleanupDb.MergePublications) } catch { $cleanupFailures += $PSItem }
            }
            foreach ($publication in $cleanupPublications) {
                try { $publication.Remove() } catch { $cleanupFailures += $PSItem }
            }
            foreach ($option in "merge publish", "publish") {
                try {
                    $null = $cleanup.ConnectionContext.ExecuteNonQuery("EXEC sys.sp_replicationdboption @dbname = N'$cleanupName', @optname = N'$option', @value = N'false'")
                } catch {
                    $cleanupFailures += $PSItem
                }
            }
        }
        $cleanupReplication = New-Object Microsoft.SqlServer.Replication.ReplicationServer -ArgumentList $cleanup.ConnectionContext
        try {
            $cleanupReplication.Refresh()
            $cleanupReplication.DistributionPublishers.Refresh()
            foreach ($registered in @($cleanupReplication.DistributionPublishers)) { $registered.Remove($true) }
            $cleanupReplication.DistributionDatabases.Refresh()
            $distribution = $cleanupReplication.DistributionDatabases[$distributionName]
            if ($distribution) { $distribution.Remove() }
            $cleanupReplication.Refresh()
            if ($cleanupReplication.IsDistributor) { $cleanupReplication.UninstallDistributor($false) }
        } catch {
            $cleanupFailures += $PSItem
        }
        $cleanupReplication.Refresh()
        if ($cleanupReplication.IsDistributor) { $cleanupReplication.UninstallDistributor($true) }
        if ([int]$cleanup.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.databases WHERE name = N'$distributionName'") -ne 0) {
            $null = $cleanup.ConnectionContext.ExecuteNonQuery("DROP DATABASE [$distributionName]")
        }
        foreach ($cleanupName in $dbName, $vpDbName) {
            try {
                $null = $cleanup.ConnectionContext.ExecuteNonQuery("EXEC sys.sp_removedbreplication @dbname = N'$cleanupName'")
            } catch {
                $cleanupFailures += $PSItem
            }
            for ($attempt = 0; $attempt -lt 3; $attempt++) {
                if ([int]$cleanup.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.databases WHERE name = N'$cleanupName'") -eq 0) { break }
                try {
                    $null = $cleanup.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$cleanupName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE")
                    $null = $cleanup.ConnectionContext.ExecuteNonQuery("DROP DATABASE [$cleanupName]")
                } catch {
                    $cleanupFailures += $PSItem
                    Start-Sleep -Seconds 2
                }
            }
        }
        [int]$cleanup.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.servers WHERE is_distributor = 1") | Should -Be 0 -Because ($cleanupFailures -join " | ")
        $cleanup.ConnectionContext.Disconnect()
    }

    It "returns one row per replicated column of every article, with the pinned notes and default view" {
        $warnings = @()
        # Each row is read as it arrives, before the command writes the next one.
        $rows = @(Get-DbaReplArticleColumn -SqlInstance $instance -Database $dbName -WarningVariable warnings -EnableException | ForEach-Object {
                [PSCustomObject]@{
                    ArticleName       = $PSItem.ArticleName
                    ColumnName        = $PSItem.ColumnName
                    PublicationName   = $PSItem.PublicationName
                    DatabaseName      = $PSItem.DatabaseName
                    ArticleId         = $PSItem.ArticleId
                    VerticalPartition = $PSItem.VerticalPartition
                    SourceObjectOwner = $PSItem.SourceObjectOwner
                    SourceObjectName  = $PSItem.SourceObjectName
                    InstanceName      = $PSItem.InstanceName
                    ComputerName      = $PSItem.ComputerName
                    SqlInstance       = $PSItem.SqlInstance
                    View              = @($PSItem.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
                }
            })
        $warnings | Should -BeNullOrEmpty -Because ($warnings -join " | ")
        @($rows | Where-Object ArticleName -eq "ColAlpha" | ForEach-Object ColumnName) | Should -Be $tableColumns["ColAlpha"]
        # The vertically partitioned article returns only the columns it publishes, in column order.
        @($rows | Where-Object ArticleName -eq "ColBeta" | ForEach-Object ColumnName) | Should -Be @("Id", "Val", "Tail")
        @($rows | Where-Object ArticleName -eq "ColGamma" | ForEach-Object ColumnName) | Should -Be $tableColumns["ColGamma"]
        $rows.Count | Should -Be (3 + 3 + $tableColumns["ColGamma"].Count)
        foreach ($row in $rows) {
            $row.DatabaseName | Should -BeExactly $dbName
            $row.SourceObjectName | Should -BeExactly $row.ArticleName
            $row.InstanceName | Should -BeExactly $fixtureServer.ServiceName
            $row.ComputerName | Should -Not -BeNullOrEmpty
            $row.SqlInstance | Should -BeOfType Microsoft.SqlServer.Management.Smo.Server
            $row.View | Should -Be $expectedView
        }
        @($rows | Where-Object ArticleName -eq "ColBeta" | ForEach-Object VerticalPartition) | Should -Not -Contain $false
        @($rows | Where-Object ArticleName -ne "ColBeta" | ForEach-Object VerticalPartition) | Should -Not -Contain $true
        @($rows | Where-Object ArticleName -ne "ColGamma" | Where-Object { $PSItem.ArticleId -le 0 }).Count | Should -Be 0
        @($rows | Where-Object ArticleName -eq "ColBeta" | ForEach-Object SourceObjectOwner) | Should -Not -Contain "dbo"
        @($rows | Where-Object ArticleName -eq "ColGamma" | ForEach-Object PublicationName) | Should -Not -Contain $transPubName
    }

    It "returns a distinct object for each column when the rows are collected" {
        # Correction same-article-object: each row keeps the article's type, notes and default view, and its own column.
        $transRows = @(Get-DbaReplArticleColumn -SqlInstance $instance -Database $dbName -Publication $transPubName -Article "ColAlpha" -EnableException)
        $transRows.Count | Should -Be 3
        @($transRows | ForEach-Object ColumnName) | Should -Be $tableColumns["ColAlpha"]
        [object]::ReferenceEquals($transRows[0], $transRows[1]) | Should -BeFalse
        foreach ($row in $transRows) {
            $row | Should -BeOfType Microsoft.SqlServer.Replication.TransArticle
            $row.Name | Should -BeExactly "ColAlpha"
            $row.ArticleName | Should -BeExactly "ColAlpha"
            $row.PublicationName | Should -BeExactly $transPubName
            $row.SqlInstance | Should -BeOfType Microsoft.SqlServer.Management.Smo.Server
            @($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Be $expectedView
        }
        $mergeRows = @(Get-DbaReplArticleColumn -SqlInstance $instance -Database $dbName -Publication $mergePubName -EnableException)
        @($mergeRows | ForEach-Object ColumnName) | Should -Be $tableColumns["ColGamma"]
        foreach ($row in $mergeRows) {
            $row | Should -BeOfType Microsoft.SqlServer.Replication.MergeArticle
            $row.ArticleName | Should -BeExactly "ColGamma"
        }
    }

    It "filters by column without case, and by publication and article" {
        $byColumn = @(Get-DbaReplArticleColumn -SqlInstance $instance -Database $dbName -Column "VAL" -EnableException | ForEach-Object { "$($PSItem.ArticleName).$($PSItem.ColumnName)" })
        @($byColumn | Sort-Object) | Should -Be @("ColAlpha.Val", "ColBeta.Val", "ColGamma.Val")

        $splatArticle = @{
            SqlInstance     = $instance
            Database        = $dbName
            Publication     = $transPubName.ToUpperInvariant()
            Article         = "colbeta"
            EnableException = $true
        }
        @(Get-DbaReplArticleColumn @splatArticle | ForEach-Object ColumnName) | Should -Be @("Id", "Val", "Tail")
        # A column the article does not publish is not returned.
        @(Get-DbaReplArticleColumn @splatArticle -Column "Secret").Count | Should -Be 0
        @(Get-DbaReplArticleColumn -SqlInstance $instance -Database $dbName -Publication $mergePubName -Article "ColAlpha" -EnableException).Count | Should -Be 0
    }

    It "returns each publication's own columns when two publications have an article of the same name" {
        # Correction vp-publication-scope: article names are unique only within a publication.
        $warnings = @()
        $one = @(Get-DbaReplArticleColumn -SqlInstance $instance -Database $vpDbName -Publication $vpPubOne -WarningVariable warnings -EnableException | ForEach-Object { "$($PSItem.PublicationName)|$($PSItem.ArticleName)|$($PSItem.ColumnName)|$($PSItem.VerticalPartition)" })
        $one | Should -Be @("$vpPubOne|DupArt|Id|True", "$vpPubOne|DupArt|A|True", "$vpPubOne|DupArt|B|True") -Because ($warnings -join " | ")
        $two = @(Get-DbaReplArticleColumn -SqlInstance $instance -Database $vpDbName -Publication $vpPubTwo -WarningVariable warnings -EnableException | ForEach-Object { "$($PSItem.PublicationName)|$($PSItem.ArticleName)|$($PSItem.ColumnName)|$($PSItem.VerticalPartition)" })
        $two | Should -Be @("$vpPubTwo|DupArt|Id|True", "$vpPubTwo|DupArt|A|True", "$vpPubTwo|DupArt|C|True") -Because ($warnings -join " | ")
        $warnings | Should -BeNullOrEmpty
    }

    It "returns the published columns of a vertically partitioned merge article" {
        # Correction merge-partition: a merge article's columns are in the merge catalog, not the transactional one.
        $warnings = @()
        $rows = @(Get-DbaReplArticleColumn -SqlInstance $instance -Database $vpDbName -Publication $vpMergePubName -WarningVariable warnings -EnableException | ForEach-Object {
                [PSCustomObject]@{
                    ArticleName       = $PSItem.ArticleName
                    ColumnName        = $PSItem.ColumnName
                    VerticalPartition = $PSItem.VerticalPartition
                    Type              = $PSItem.GetType().Name
                }
            })
        @($rows | ForEach-Object ColumnName) | Should -Be $vpMergeColumns -Because ($warnings -join " | ")
        $warnings | Should -BeNullOrEmpty
        foreach ($row in $rows) {
            $row.ArticleName | Should -BeExactly "MergeT"
            $row.VerticalPartition | Should -BeTrue
            $row.Type | Should -BeExactly "MergeArticle"
        }
    }

    It "runs once per piped publication name" -Tag "NativeChecklist:pipeline-multiple" {
        # -SqlInstance is bound by name, so each piped name binds -Publication and runs its own process block.
        $piped = @(@($mergePubName, $transPubName) | Get-DbaReplArticleColumn -SqlInstance $instance -Database $dbName -EnableException | ForEach-Object { "$($PSItem.PublicationName)|$($PSItem.ArticleName)" })
        $piped.Count | Should -Be ($tableColumns["ColGamma"].Count + 6)
        @($piped | Select-Object -First $tableColumns["ColGamma"].Count | Select-Object -Unique) | Should -Be @("$mergePubName|ColGamma")
        @($piped | Select-Object -Skip $tableColumns["ColGamma"].Count | ForEach-Object { $PSItem.Split("|")[0] } | Select-Object -Unique) | Should -Be @($transPubName)
    }

    It "keeps going after a failed instance when EnableException is false" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $warnings = @()
        $splatKeepGoing = @{
            SqlInstance     = $badInstance, $instance
            Database        = $dbName
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "warnings"
        }
        $output = @(Get-DbaReplArticleColumn @splatKeepGoing | ForEach-Object ColumnName)
        # Only the warnings that are not the bad instance's own connection failure (the nested command's and the connect
        # warning) explain a short count.
        $otherWarnings = @($warnings | Where-Object { "$PSItem" -notlike "*Error connecting to *" })
        $output.Count | Should -Be (3 + 3 + $tableColumns["ColGamma"].Count) -Because ($otherWarnings -join " | ")
        ($warnings -join " ") | Should -BeLike "*Error occurred while establishing connection to * | Error connecting to *"
    }

    It "adds exactly one record per failed connection to -ErrorVariable and `$Error in every error mode" {
        # harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5: the port's complete
        # sequences, entry by entry. The pin's entries per mode stand beside these in the item's notes/error-records-20261112.md
        # (probe vpquery, both editions). The record's content equals the pin's Stop-Function record measured there: type
        # System.Exception carrying the connection failure's own text over the SqlException, ConnectionError, reason Exception,
        # target the failed instance; its id, empty Activity and missing ErrorDetails are point 4's form.
        function Get-NativeErrorHead { if ($global:Error.Count -gt 0) { $global:Error[0] } }
        function Get-NativeAddedErrors($head) {
            $added = New-Object System.Collections.ArrayList
            foreach ($entry in $global:Error) {
                if ($null -ne $head -and [object]::ReferenceEquals($entry, $head)) { break }
                $null = $added.Add($entry)
            }
            , $added.ToArray()
        }
        function Assert-NativeConnectRecord($record, $id) {
            $record | Should -BeOfType System.Management.Automation.ErrorRecord
            $record.FullyQualifiedErrorId | Should -BeExactly $id
            "$($record.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($record.CategoryInfo.Reason)" | Should -BeExactly "Exception"
            "$($record.TargetObject)" | Should -BeExactly "localhost,1"
            $record.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $record.Exception.Message | Should -BeExactly $record.Exception.GetBaseException().Message
            $record.Exception.InnerException.GetType().Name | Should -BeExactly "SqlException"
        }
        $plainId = "dbatools_Get-DbaReplArticle"
        $thrownId = "dbatools_Get-DbaReplArticle,Dataplat.Dbatools.Commands.GetDbaReplArticleColumnCommand"
        $splatBase = @{
            SqlInstance   = $badInstance, $instance
            Database      = $dbName
            Publication   = $transPubName
            WarningAction = "SilentlyContinue"
        }

        # Plain, -ErrorAction SilentlyContinue and -ErrorAction Stop all go on to the next instance (the pin's Stop-Function
        # writes its record and continues): -ErrorVariable and $Error each gain the one record.
        foreach ($action in "Continue", "SilentlyContinue", "Stop") {
            $errors = @()
            $head = Get-NativeErrorHead
            $rows = @(Get-DbaReplArticleColumn @splatBase -EnableException:$false -ErrorAction $action -ErrorVariable errors)
            $added = @(Get-NativeAddedErrors $head)
            $rows.Count | Should -Be 6 -Because "-ErrorAction $action"
            @($errors).Count | Should -Be 1 -Because ("-ErrorAction $($action): " + (@($errors | ForEach-Object { "$($PSItem.GetType().Name):$($PSItem.FullyQualifiedErrorId)" }) -join " | "))
            Assert-NativeConnectRecord $errors[0] $plainId
            @($added).Count | Should -Be 1 -Because ("-ErrorAction $($action): " + (@($added | ForEach-Object { "$($PSItem.GetType().Name):$($PSItem.FullyQualifiedErrorId)" }) -join " | "))
            # $Error holds its own entry of the record (run f70af372: not the -ErrorVariable object), with the same content.
            Assert-NativeConnectRecord $added[0] $plainId
            $added[0].Exception.Message | Should -BeExactly $errors[0].Exception.Message
        }

        # A caller's try without -EnableException: nothing is thrown, the same one record.
        $errors = @()
        $thrown = $false
        $head = Get-NativeErrorHead
        try {
            $rows = @(Get-DbaReplArticleColumn @splatBase -ErrorVariable errors)
        } catch {
            $thrown = $true
        }
        $added = @(Get-NativeAddedErrors $head)
        $thrown | Should -BeFalse
        $rows.Count | Should -Be 6
        @($errors).Count | Should -Be 1
        Assert-NativeConnectRecord $errors[0] $plainId
        @($added).Count | Should -Be 1
        Assert-NativeConnectRecord $added[0] $plainId
        $added[0].Exception.Message | Should -BeExactly $errors[0].Exception.Message

        # -EnableException in a caller's try: the stop's one CmdletInvocationException in -ErrorVariable ("The -ErrorVariable
        # entry of a native -EnableException stop (operator, 2026-11-06)"), the thrown record alone in $Error.
        $errors = @()
        $caught = $null
        $rows = @()
        $head = Get-NativeErrorHead
        try {
            $rows = @(Get-DbaReplArticleColumn @splatBase -EnableException -ErrorVariable errors)
        } catch {
            $caught = $PSItem
        }
        $added = @(Get-NativeAddedErrors $head)
        $rows.Count | Should -Be 0
        Assert-NativeConnectRecord $caught $thrownId
        @($errors).Count | Should -Be 1 -Because (@($errors | ForEach-Object { $PSItem.GetType().FullName }) -join " | ")
        $errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
        $errors[0].ErrorRecord.FullyQualifiedErrorId | Should -BeExactly $thrownId
        @($added).Count | Should -Be 1
        $added[0].FullyQualifiedErrorId | Should -BeExactly $thrownId
        $added[0].Exception.Message | Should -BeExactly $caught.Exception.Message
    }

    It "stops at a failed connection with -EnableException, with the nested command's record" -Tag "NativeChecklist:enable-exception" {
        $failure = $null
        $output = @()
        $warnings = @()
        try {
            $output = @(Get-DbaReplArticleColumn -SqlInstance $badInstance, $instance -Database $dbName -WarningVariable warnings -EnableException)
        } catch {
            $failure = $PSItem
        }
        $failure | Should -Not -BeNullOrEmpty
        # The pin's record comes from the nested Get-DbaReplArticle's Stop-Function; the port reports it under its own
        # cmdlet type (harness-edits.md, "Child-command error owner and further checks by the manager", point 1).
        $failure.FullyQualifiedErrorId | Should -BeExactly "dbatools_Get-DbaReplArticle,Dataplat.Dbatools.Commands.GetDbaReplArticleColumnCommand"
        $failure.CategoryInfo.Category | Should -Be "ConnectionError"
        $output.Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Error occurred while establishing connection to * | Error connecting to *"
    }
}

Describe "Native Get-DbaReplArticleColumn over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $sqlLoginInstance = $TestConfig.InstanceSqlLogin
    }

    It "reads the SQL-login instance with its credential" -Tag "NativeChecklist:sql-login" {
        $server = Connect-DbaInstance -SqlInstance $sqlLoginInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException
        [int]$server.ConnectionContext.ExecuteScalar("SELECT IS_SRVROLEMEMBER('sysadmin')") | Should -Be 1
        $warnings = @()
        $splatSqlLogin = @{
            SqlInstance     = $sqlLoginInstance
            SqlCredential   = $TestConfig.SqlLoginCred
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "warnings"
        }
        $null = Get-DbaReplArticleColumn @splatSqlLogin
        $warnings | Should -BeNullOrEmpty -Because ($warnings -join " | ")
        { $null = Get-DbaReplArticleColumn -SqlInstance $sqlLoginInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException } | Should -Not -Throw
    }

    It "rejects the SQL-login instance without its credential" -Tag "NativeChecklist:sql-login" {
        # Pin public/Get-DbaReplArticleColumn.ps1: $articles = Get-DbaReplArticle -SqlInstance $SqlInstance -SqlCredential $SqlCredential ...
        #     -EnableException:$EnableException, outside its try. The nested command's catch around Connect-DbaInstance warns and
        # continues, and under -EnableException its Stop-Function -Continue throws through this command.
        $warnings = @()
        $splatNoCredential = @{
            SqlInstance     = $sqlLoginInstance
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "warnings"
        }
        @(Get-DbaReplArticleColumn @splatNoCredential).Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Error occurred while establishing connection to $sqlLoginInstance | Error connecting to *"
        $failure = $null
        try {
            $null = Get-DbaReplArticleColumn -SqlInstance $sqlLoginInstance -EnableException
        } catch {
            $failure = $PSItem
        }
        $failure | Should -Not -BeNullOrEmpty
        $failure.FullyQualifiedErrorId | Should -BeExactly "dbatools_Get-DbaReplArticle,Dataplat.Dbatools.Commands.GetDbaReplArticleColumnCommand"
        $failure.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Get-DbaReplArticleColumn refuses Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per call.
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
    }

    AfterAll {
        if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
    }

    It "refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "warnings"
        }
        @(Get-DbaReplArticleColumn @splatAzure).Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Error occurred while establishing connection to *Azure SQL Database not supported*"
        { $null = Get-DbaReplArticleColumn -SqlInstance $azureServer -EnableException } | Should -Throw "*Azure SQL Database not supported*"
    }
}
