#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaReplArticle",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads publication articles.
# NativeChecklist: azure-sqldb N/A -- Azure SQL Database can only be a push subscriber; it cannot be a publisher, so it holds no publications or articles: https://learn.microsoft.com/azure/azure-sql/database/replication-to-sql-database; the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.

Describe "Native Get-DbaReplArticle" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        # Unique names per run, so legs never touch each other's objects.
        $suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $dbName = "dbatoolsci_replart_$suffix"
        $transPubName = "dbatoolsci_tpub_$suffix"
        $mergePubName = "dbatoolsci_mpub_$suffix"
        $missingDbName = "dbatoolsci_nodb_$suffix"
        $badInstance = "Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False"
        $expectedView = @("ComputerName", "InstanceName", "SqlInstance", "DatabaseName", "PublicationName", "Name", "Type", "VerticalPartition", "SourceObjectOwner", "SourceObjectName")

        # Makes the instance its own distributor and local publisher through RMO, as Microsoft Learn's
        # ReplicationDatabase example does. It refuses an instance that already has replication configured.
        $fixtureServer = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        $replication = New-Object Microsoft.SqlServer.Replication.ReplicationServer -ArgumentList $fixtureServer.ConnectionContext
        if ($replication.IsDistributor -or $replication.IsPublisher -or [int]$fixtureServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.servers WHERE is_distributor = 1") -ne 0) {
            throw "Native article fixture requires an instance without existing distribution or publishing; existing configuration was not changed."
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

        # A database with two transactional articles in two schemas and one merge article.
        $null = $fixtureServer.ConnectionContext.ExecuteNonQuery("CREATE DATABASE [$dbName]")
        $fixtureServer.Databases.Refresh()
        $fixtureDb = $fixtureServer.Databases[$dbName]
        $null = $fixtureDb.ExecuteNonQuery("CREATE SCHEMA artsales")
        $null = $fixtureDb.ExecuteNonQuery("CREATE TABLE dbo.ArtAlpha (Id int NOT NULL PRIMARY KEY, Val nvarchar(20) NULL)")
        $null = $fixtureDb.ExecuteNonQuery("CREATE TABLE artsales.ArtBeta (Id int NOT NULL PRIMARY KEY, Val nvarchar(20) NULL)")
        $null = $fixtureDb.ExecuteNonQuery("CREATE TABLE dbo.ArtGamma (Id int NOT NULL PRIMARY KEY, Val nvarchar(20) NULL)")

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
        foreach ($source in @(@("ArtAlpha", "dbo"), @("ArtBeta", "artsales"))) {
            $article = New-Object Microsoft.SqlServer.Replication.TransArticle
            $article.ConnectionContext = $fixtureServer.ConnectionContext
            $article.Name = $source[0]
            $article.DatabaseName = $dbName
            $article.SourceObjectName = $source[0]
            $article.SourceObjectOwner = $source[1]
            $article.PublicationName = $transPubName
            $article.Type = [Microsoft.SqlServer.Replication.ArticleOptions]::LogBased
            $article.Create()
        }

        $mergePub = New-Object Microsoft.SqlServer.Replication.MergePublication
        $mergePub.ConnectionContext = $fixtureServer.ConnectionContext
        $mergePub.DatabaseName = $dbName
        $mergePub.Name = $mergePubName
        $mergePub.Create()
        $mergeArticle = New-Object Microsoft.SqlServer.Replication.MergeArticle
        $mergeArticle.ConnectionContext = $fixtureServer.ConnectionContext
        $mergeArticle.Name = "ArtGamma"
        $mergeArticle.DatabaseName = $dbName
        $mergeArticle.SourceObjectName = "ArtGamma"
        $mergeArticle.SourceObjectOwner = "dbo"
        $mergeArticle.PublicationName = $mergePubName
        $mergeArticle.Type = [Microsoft.SqlServer.Replication.ArticleOptions]::TableBased
        $mergeArticle.Create()
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
        $cleanupDb = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase -ArgumentList $dbName, $cleanup.ConnectionContext
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
                $null = $cleanup.ConnectionContext.ExecuteNonQuery("EXEC sys.sp_replicationdboption @dbname = N'$dbName', @optname = N'$option', @value = N'false'")
            } catch {
                $cleanupFailures += $PSItem
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
        try {
            $null = $cleanup.ConnectionContext.ExecuteNonQuery("EXEC sys.sp_removedbreplication @dbname = N'$dbName'")
        } catch {
            $cleanupFailures += $PSItem
        }
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            if ([int]$cleanup.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.databases WHERE name = N'$dbName'") -eq 0) { break }
            try {
                $null = $cleanup.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE")
                $null = $cleanup.ConnectionContext.ExecuteNonQuery("DROP DATABASE [$dbName]")
            } catch {
                $cleanupFailures += $PSItem
                Start-Sleep -Seconds 2
            }
        }
        [int]$cleanup.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.servers WHERE is_distributor = 1") | Should -Be 0 -Because ($cleanupFailures -join " | ")
        $cleanup.ConnectionContext.Disconnect()
    }

    It "returns every article of the database's publications with the pinned default view" {
        $warnings = @()
        $articles = @(Get-DbaReplArticle -SqlInstance $instance -Database $dbName -WarningVariable warnings -EnableException)
        $warnings | Should -BeNullOrEmpty -Because ($warnings -join " | ")
        $articles.Count | Should -Be 3
        # Transactional publications come first, then merge publications, as the pinned TransPublications + MergePublications.
        $articles[0] | Should -BeOfType Microsoft.SqlServer.Replication.TransArticle
        $articles[1] | Should -BeOfType Microsoft.SqlServer.Replication.TransArticle
        $articles[2] | Should -BeOfType Microsoft.SqlServer.Replication.MergeArticle
        @($articles[0].Name, $articles[1].Name) | Sort-Object | Should -Be @("ArtAlpha", "ArtBeta")
        $articles[2].Name | Should -BeExactly "ArtGamma"
        $articles[2].PublicationName | Should -BeExactly $mergePubName
        $articles[2].Type.ToString() | Should -BeExactly "TableBased"
        $beta = $articles | Where-Object Name -eq "ArtBeta"
        $beta.SourceObjectOwner | Should -BeExactly "artsales"
        $beta.SourceObjectName | Should -BeExactly "ArtBeta"
        $beta.PublicationName | Should -BeExactly $transPubName
        $beta.Type.ToString() | Should -BeExactly "LogBased"
        $beta.VerticalPartition | Should -BeFalse
        foreach ($article in $articles) {
            $article.DatabaseName | Should -BeExactly $dbName
            $article.ComputerName | Should -Not -BeNullOrEmpty
            $article.InstanceName | Should -BeExactly $fixtureServer.ServiceName
            # The pin decorates SqlInstance with the connected server object itself.
            $article.SqlInstance | Should -BeOfType Microsoft.SqlServer.Management.Smo.Server
            $article.SqlInstance.Name | Should -BeExactly $fixtureServer.Name
            $article.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be $expectedView
        }
    }

    It "finds the articles without -Database and filters by publication, schema and name without case" {
        @(Get-DbaReplArticle -SqlInstance $instance -EnableException | Where-Object DatabaseName -eq $dbName).Count | Should -Be 3

        $byPublication = @(Get-DbaReplArticle -SqlInstance $instance -Database $dbName -Publication $transPubName.ToUpperInvariant() -EnableException)
        @($byPublication.Name | Sort-Object) | Should -Be @("ArtAlpha", "ArtBeta")

        $bySchema = @(Get-DbaReplArticle -SqlInstance $instance -Database $dbName -Schema "ARTSALES" -EnableException)
        $bySchema.Count | Should -Be 1
        $bySchema[0].Name | Should -BeExactly "ArtBeta"

        $byName = @(Get-DbaReplArticle -SqlInstance $instance -Database $dbName -Name "artgamma" -EnableException)
        $byName.Count | Should -Be 1
        $byName[0] | Should -BeOfType Microsoft.SqlServer.Replication.MergeArticle

        $byBoth = @(Get-DbaReplArticle -SqlInstance $instance -Database $dbName -Publication $transPubName -Schema "dbo" -Name "ArtAlpha", "ArtGamma" -EnableException)
        $byBoth.Count | Should -Be 1
        $byBoth[0].Name | Should -BeExactly "ArtAlpha"

        @(Get-DbaReplArticle -SqlInstance $instance -Database $dbName -Publication $mergePubName -Name "ArtAlpha" -EnableException).Count | Should -Be 0
        @(Get-DbaReplArticle -SqlInstance $instance -Database $missingDbName -EnableException).Count | Should -Be 0
    }

    It "keeps going after a failed pipeline instance with -EnableException:`$false" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $warnings = @()
        $splatPipeline = @{
            Database        = $dbName
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "warnings"
        }
        # A connected server object, as Connect-DbaInstance | Get-DbaReplArticle passes it, after a target that cannot connect.
        $pipedServer = Connect-DbaInstance -SqlInstance $instance -EnableException
        $output = @(@($badInstance, $pipedServer) | Get-DbaReplArticle @splatPipeline)
        $output.Count | Should -Be 3 -Because ($warnings -join " | ")
        @($output | Where-Object DatabaseName -ne $dbName).Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Error occurred while establishing connection to * | Error connecting to *"
    }

    It "stops at a failed connection with -EnableException" -Tag "NativeChecklist:enable-exception" {
        $failure = $null
        $warnings = @()
        try {
            $null = Get-DbaReplArticle -SqlInstance $badInstance, $instance -Database $dbName -WarningVariable warnings -EnableException
        } catch {
            $failure = $PSItem
        }
        $failure | Should -Not -BeNullOrEmpty
        $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaReplArticle*"
        $failure.CategoryInfo.Category | Should -Be "ConnectionError"
        ($warnings -join " ") | Should -BeLike "*Error occurred while establishing connection to * | Error connecting to *"
    }
}

Describe "Native Get-DbaReplArticle over SQL authentication" -Tag IntegrationTests {
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
        $null = Get-DbaReplArticle @splatSqlLogin
        $warnings | Should -BeNullOrEmpty -Because ($warnings -join " | ")
        { $null = Get-DbaReplArticle -SqlInstance $sqlLoginInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException } | Should -Not -Throw
    }

    It "rejects the SQL-login instance without its credential" -Tag "NativeChecklist:sql-login" {
        # Pin public/Get-DbaReplArticle.ps1:124-127, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # Pin public/Connect-DbaInstance.ps1:499-502 and 1501-1502, verbatim:
        # if ($DisableException) {
        #     $EnableException = $false
        # } else {
        #     $EnableException = $true
        # if (-not $connectionSucceeded) {
        #     Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
        # The nested Connect-DbaInstance throws, the command's own catch warns and continues, and under -EnableException its
        # Stop-Function -Continue throws. The base already ships a cmdlet and the pin predates src/, so no buildable commit runs
        # the pinned function (source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt).
        $warnings = @()
        $splatNoCredential = @{
            SqlInstance     = $sqlLoginInstance
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "warnings"
        }
        @(Get-DbaReplArticle @splatNoCredential).Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Error occurred while establishing connection to $sqlLoginInstance | Error connecting to *"
        $failure = $null
        try {
            $null = Get-DbaReplArticle -SqlInstance $sqlLoginInstance -EnableException
        } catch {
            $failure = $PSItem
        }
        $failure | Should -Not -BeNullOrEmpty
        $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaReplArticle*"
        $failure.CategoryInfo.Category | Should -Be "ConnectionError"
    }
}

Describe "Native Get-DbaReplArticle refuses Azure SQL Database" -Tag IntegrationTests {
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
        @(Get-DbaReplArticle @splatAzure).Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Error occurred while establishing connection to *Azure SQL Database not supported*"
        { $null = Get-DbaReplArticle -SqlInstance $azureServer -EnableException } | Should -Throw "*Azure SQL Database not supported*"
    }
}
