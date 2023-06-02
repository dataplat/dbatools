Describe "Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sqladmin", $password

        $PSDefaultParameterValues["*:SqlInstance"] = "mssql1"
        $PSDefaultParameterValues["*:SqlCredential"] = $cred
        $PSDefaultParameterValues["*:SubscriptionSqlCredential1"] = $cred
        $PSDefaultParameterValues["*:Confirm"] = $false
        $PSDefaultParameterValues["*:SharedPath"] = "/shared"

        #TODO: To be removed?
        $PSDefaultParameterValues["*:-SnapshotShare"] = "/shared"
        $PSDefaultParameterValues["*:WarningAction"] = "SilentlyContinue"
        $global:ProgressPreference = "SilentlyContinue"

        #$null = Get-XPlatVariable | Where-Object { $PSItem -notmatch "Copy-", "Migration" } | Sort-Object
        # load dbatools-lib
        #Import-Module dbatools-core-library
        Import-Module ./dbatools.psd1 -Force

        $null = New-DbaDatabase -Name ReplDb
        $null = Invoke-DbaQuery -Database ReplDb -Query 'CREATE TABLE ReplicateMe ( id int identity (1,1) PRIMARY KEY, col1 varchar(10) ); CREATE TABLE ReplicateMeToo ( id int identity (1,1) PRIMARY KEY, col1 varchar(10) );'

    }

    Describe "General commands" {

        Context "Get-DbaReplServer works" {

            It "Doesn't throw errors" {
                { Get-DbaReplServer -EnableException } | Should -Not -Throw
            }

            It "Returns a ReplicationObject" {
                (Get-DbaReplServer).GetType().BaseType | Should -Be "Microsoft.SqlServer.Replication.ReplicationObject"
            }

            It "Gets a replication server" {
                (Get-DbaReplServer).SqlInstance | Should -Be 'mssql1'
                (Get-DbaReplServer).DistributorInstalled | Should -Not -BeNullOrEmpty
                (Get-DbaReplServer).DistributorAvailable | Should -Not -BeNullOrEmpty
                (Get-DbaReplServer).IsDistributor | Should -Not -BeNullOrEmpty
                (Get-DbaReplServer).IsPublisher | Should -Not -BeNullOrEmpty
            }
        }
    }

    Describe "Publishing\Distribution commands" {

        Context "Get-DbaReplDistributor works" {
            BeforeAll {

                # if distribution is enabled, disable it & enable it with defaults
                if ((Get-DbaReplDistributor).IsDistributor) {
                    Disable-DbaReplDistributor
                }
                Enable-DbaReplDistributor
            }

            It "gets a distributor without error" {
                { Get-DbaReplDistributor -EnableException } | Should -Not -Throw
            }

            It "gets a distributor" {
                (Get-DbaReplDistributor).IsDistributor | Should -Be $true
            }

            It "distribution database name is correct" {
                (Get-DbaReplDistributor).DistributionDatabases.Name | Should -Be 'distribution'
            }

            It "can pipe a sql server object to it" -skip {
                Connect-DbaInstance | Get-DbaReplDistributor | Should -Not -BeNullOrEmpty
            }
        }

        Context "Get-DbaReplPublisher works" {
            BeforeAll {
                # if distribution is disabled - enable it
                if (-not (Get-DbaReplDistributor).IsDistributor) {
                    Enable-DbaReplDistributor
                }

                # if publishing is disabled - enable it
                if (-not (Get-DbaReplServer).IsPublisher) {
                    Enable-DbaReplPublishing -PublisherSqlLogin $cred -EnableException
                }
            }

            It "gets a publisher" {
                (Get-DbaReplPublisher).PublisherType | Should -Be "MSSQLSERVER"
            }

            It "gets a publisher using piping" -skip {
                (Connect-DbaInstance | Get-DbaReplPublisher).PublisherType | Should -Be "MSSQLSERVER"
            }

        }

        Context "Enable-DbaReplDistributor works" {
            BeforeAll {
                # if distribution is enabled - disable it
                if ((Get-DbaReplDistributor).IsDistributor) {
                    Disable-DbaReplDistributor
                }
            }

            It "distribution starts disabled" {
                (Get-DbaReplDistributor).IsDistributor | Should -Be $false
            }

            It "distribution is enabled" {
                Enable-DbaReplDistributor
                (Get-DbaReplDistributor).IsDistributor | Should -Be $true
            }
        }

        Context "Enable-DbaReplDistributor works with specified database name" {
            BeforeAll {
                # if distribution is enabled - disable it
                if ((Get-DbaReplDistributor).IsDistributor) {
                    Disable-DbaReplDistributor
                }
            }
            AfterAll {
                if ((Get-DbaReplDistributor).IsDistributor) {
                    Disable-DbaReplDistributor
                }
            }

            It "distribution starts disabled" {
                (Get-DbaReplDistributor).IsDistributor | Should -Be $false
            }

            It "distribution is enabled with specific database" {
                $distDb = ('distdb-{0}' -f (Get-Random))
                Enable-DbaReplDistributor -DistributionDatabase $distDb
                (Get-DbaReplDistributor).DistributionDatabases.Name | Should -Be $distDb
            }
        }

        Context "Disable-DbaReplDistributor works" {
            BeforeAll {
                # if replication is disabled - enable it
                if (-not (Get-DbaReplDistributor).IsDistributor) {
                    Enable-DbaReplDistributor
                }
            }

            It "distribution starts enabled" {
                (Get-DbaReplDistributor).IsDistributor | Should -Be $true
            }

            It "distribution is disabled" {
                Disable-DbaReplDistributor
                (Get-DbaReplDistributor).IsDistributor | Should -Be $false
            }
        }

        Context "Enable-DbaReplPublishing works" {
            BeforeAll {
                # if Publishing is enabled - disable it
                if ((Get-DbaReplServer).IsPublisher) {
                    Disable-DbaReplPublishing
                }
                # if distribution is disabled - enable it
                if (-not (Get-DbaReplDistributor).IsDistributor) {
                    Enable-DbaReplDistributor
                }
            }

            It "publishing starts disabled" {
                (Get-DbaReplServer).IsPublisher | Should -Be $false
            }

            It "publishing is enabled" {
                { Enable-DbaReplPublishing -EnableException } | Should -Not -Throw
                (Get-DbaReplServer).IsPublisher | Should -Be $true
            }
        }

        Context "Disable-DbaReplPublishing works" {
            BeforeAll {
                # if publishing is disabled - enable it
                if (-not (Get-DbaReplServer).IsPublisher) {
                    write-output -message 'I should enable publishing'
                    Enable-DbaReplPublishing -EnableException
                }

                # if distribution is disabled - enable it
                if (-not (Get-DbaReplDistributor).IsDistributor) {
                    write-output -message 'I should enable distribution'
                    Enable-DbaReplDistributor -EnableException
                }
            }

            It "publishing starts enabled" {
                (Get-DbaReplServer).IsPublisher | Should -Be $true
            }

            It "publishing is disabled" {
                { Disable-DbaReplPublishing -EnableException } | Should -Not -Throw
                (Get-DbaReplServer).IsPublisher | Should -Be $false
            }
        }
    }

    Describe "Publication commands" {

        Context "Get-DbaReplPublication works" {
            BeforeAll {
                # if distribution is disabled - enable it
                if (-not (Get-DbaReplDistributor).IsDistributor) {
                    Enable-DbaReplDistributor
                }

                # if publishing is disabled - enable it
                if (-not (Get-DbaReplServer).IsPublisher) {
                    Enable-DbaReplPublishing -PublisherSqlLogin $cred -EnableException
                }

                # create a publication
                $name = 'TestPub'
                New-DbaReplPublication -Database ReplDb -Type Transactional -PublicationName ('{0}-Trans' -f $Name)
                New-DbaReplPublication -Database ReplDb -Type Merge -PublicationName ('{0}-Merge' -f $Name)
                $null = New-DbaDatabase -Name Test
                New-DbaReplPublication -Database Test -Type Snapshot -PublicationName ('{0}-Snapshot' -f $Name)
            }

            It "gets all publications" {
                Get-DbaReplPublication | Should -Not -BeNullOrEmpty
            }

            It "gets publications for a specific database" {
                Get-DbaReplPublication -Database ReplDb | Should -Not -BeNullOrEmpty
                (Get-DbaRepPublication -Database ReplDb).DatabaseName | ForEach-Object { $_ | Should -Be 'ReplDb' }
            }

            It "gets publications for a specific type" {
                Get-DbaReplPublication -Type Transactional | Should -Not -BeNullOrEmpty
                (Get-DbaRepPublication -Type Transactional).Type | ForEach-Object { $_ | Should -Be 'Transactional' }
            }

            It "works with piping" -skip {
                Connect-DbaInstance | Get-DbaReplPublication | Should -Not -BeNullOrEmpty
            }
        }

        Context "New-DbaReplPublication works" {
            BeforeAll {
                # if replication is disabled - enable it
                if (-not (Get-DbaReplDistributor).IsDistributor) {
                    Enable-DbaReplDistributor
                }
                # if publishing is disabled - enable it
                if (-not (Get-DbaReplServer).IsPublisher) {
                    Enable-DbaReplPublishing -PublisherSqlLogin $cred -EnableException
                }
            }

            It "New-DbaReplPublication creates a Transactional publication" {
                $name = 'TestPub'
                { New-DbaReplPublication -Database ReplDb -Type Transactional -PublicationName $Name -EnableException } | Should -Not -Throw
                (Get-DbaReplPublication -Name $Name) | Should -Not -BeNullOrEmpty
                (Get-DbaReplPublication -Name $Name).DatabaseName | Should -Be 'ReplDb'
                (Get-DbaReplPublication -Name $Name).Type | Should -Be 'Transactional'
            }
            It "New-DbaReplPublication creates a Snapshot publication" {
                $name = 'Snappy'
                { New-DbaReplPublication -Database ReplDb -Type Snapshot -PublicationName $name -EnableException } | Should -Not -Throw
                (Get-DbaReplPublication -Name $name) | Should -Not -BeNullOrEmpty
                (Get-DbaReplPublication -Name $name).DatabaseName | Should -Be 'ReplDb'
                (Get-DbaReplPublication -Name $name).Type | Should -Be 'Snapshot'
            }
            It "New-DbaReplPublication creates a Merge publication" {
                $name = 'Mergey'
                { New-DbaReplPublication -Database ReplDb -Type Merge -PublicationName $name -EnableException } | Should -Not -Throw
                (Get-DbaReplPublication -Name $name) | Should -Not -BeNullOrEmpty
                (Get-DbaReplPublication -Name $name).DatabaseName | Should -Be 'ReplDb'
                (Get-DbaReplPublication -Name $name).Type | Should -Be 'Merge'
            }
        }

        Context "Remove-DbaReplPublication works" {
            # TODO:
        }
    }

    Describe "Article commands" {
        BeforeAll {
            # if replication is disabled - enable it
            if (-not (Get-DbaReplDistributor).IsDistributor) {
                Enable-DbaReplDistributor
            }
            # if publishing is disabled - enable it
            if (-not (Get-DbaReplServer).IsPublisher) {
                Enable-DbaReplPublishing -PublisherSqlLogin $cred -EnableException
            }
            # we need some publications too
            $name = 'TestTrans'
            if (-not (Get-DbaReplPublication -Name $name -Type Transactional )) {
                $null = New-DbaReplPublication -Database ReplDb -Type Transactional -PublicationName $Name
            }
            $name = 'TestSnap'
            if (-not (Get-DbaReplPublication -Name $name -Type Snapshot)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -PublicationName $Name
            }
            $name = 'TestMerge'
            if (-not (Get-DbaReplPublication -Name $name -Type Merge)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Merge -PublicationName $Name
            }
            $article = 'ReplicateMe'
            $article2 = 'ReplicateMeToo'
        }

        Context "New-DbaReplCreationScriptOptions works" {
            It "New-DbaReplCreationScriptOptions creates a Microsoft.SqlServer.Replication.CreationScriptOptions" {
                $options = New-DbaReplCreationScriptOptions
                $options | Should -BeOfType Microsoft.SqlServer.Replication.CreationScriptOptions
            }
            It "Microsoft.SqlServer.Replication.CreationScriptOptions should include the 11 defaults by default" {
                ((New-DbaReplCreationScriptOptions).ToString().Split(',').Trim() | Measure-Object).Count | Should -Be 11
            }
            It "Microsoft.SqlServer.Replication.CreationScriptOptions should include ClusteredIndexes" {
                ((New-DbaReplCreationScriptOptions).ToString().Split(',').Trim() | Should -Contain 'ClusteredIndexes')
            }
            It "Microsoft.SqlServer.Replication.CreationScriptOptions with option of NonClusteredIndexes should add NonClusteredIndexes" {
                ((New-DbaReplCreationScriptOptions -Option NonClusteredIndexes).ToString().Split(',').Trim() | Measure-Object).Count | Should -Be 12
                ((New-DbaReplCreationScriptOptions -Option NonClusteredIndexes).ToString().Split(',').Trim() | Should -Contain 'NonClusteredIndexes')
            }

            It "NoDefaults should mean Microsoft.SqlServer.Replication.CreationScriptOptions only contains DisableScripting" {
                ((New-DbaReplCreationScriptOptions -NoDefaults).ToString().Split(',').Trim() | Measure-Object).Count | Should -Be 1
                ((New-DbaReplCreationScriptOptions -NoDefaults).ToString().Split(',').Trim() | Should -Contain 'DisableScripting')
            }
            It "NoDefaults plus option of NonClusteredIndexes should mean Microsoft.SqlServer.Replication.CreationScriptOptions only contains NonClusteredIndexes" {
                ((New-DbaReplCreationScriptOptions -NoDefaults -Option NonClusteredIndexes).ToString().Split(',').Trim() | Measure-Object).Count | Should -Be 1
                ((New-DbaReplCreationScriptOptions -NoDefaults -Option NonClusteredIndexes).ToString().Split(',').Trim() | Should -Contain 'NonClusteredIndexes')
            }
        }

        Context "Add-DbaReplArticle works" {
            BeforeAll {
                # remove all articles
                $null = Get-DbaReplArticle -Database ReplDb | Remove-DbaReplArticle -Confirm:$false
            }

            It "Add-DbaReplArticle adds an article to a Transactional publication" {
                $pubName = 'TestPub'
                { Add-DbaReplArticle -Database ReplDb -Name $article -Publication $pubName -EnableException } | Should -not -throw
                $art = Get-DbaReplArticle -Database ReplDb -Name $article -Publication $pubName
                $art | Should -Not -BeNullOrEmpty
                $art.PublicationName | Should -Be $pubName
                $art.Name | Should -Be $article
            }

            It "Add-DbaReplArticle adds an article to a Snapshot publication and specifies create script options" {
                $pubname = 'TestPub'
                $cso = New-DbaReplCreationScriptOptions -Options NonClusteredIndexes, Statistics
                { Add-DbaReplArticle -Database ReplDb -Name $article2 -Publication $pubname -CreationScriptOptions $cso -EnableException } | Should -not -throw
                $art = Get-DbaReplArticle -Database ReplDb -Name $article2 -Publication $pubName
                $art | Should -Not -BeNullOrEmpty
                $art.PublicationName | Should -Be $pubName
                $art.Name | Should -Be $article2
            }

            It "Add-DbaReplArticle adds an article to a Snapshot publication" {
                $pubname = 'TestSnap'
                { Add-DbaReplArticle -Database ReplDb -Name $article -Publication $pubname -EnableException } | Should -not -throw
                $art = Get-DbaReplArticle -Database ReplDb -Name $article -Publication $pubName
                $art | Should -Not -BeNullOrEmpty
                $art.PublicationName | Should -Be $pubName
                $art.Name | Should -Be $article
            }

            It "Add-DbaReplArticle adds an article to a Snapshot publication with a filter" {
                $pubName = 'TestSnap'
                { Add-DbaReplArticle -Database ReplDb -Name $article2 -Publication $pubName -Filter "col1 = 'test'" -EnableException } | Should -not -throw
                $art = Get-DbaReplArticle -Database ReplDb -Name $article2 -Publication $pubName
                $art | Should -Not -BeNullOrEmpty
                $art.PublicationName | Should -Be $pubName
                $art.Name | Should -Be $article2
                $art.FilterClause | Should -Be "col1 = 'test'"
            }

            It "Add-DbaReplArticle adds an article to a Merge publication" {
                $pubname = 'TestMerge'
                { Add-DbaReplArticle -Database ReplDb -Name $article -Publication $pubname -EnableException } | Should -not -throw
                $art = Get-DbaReplArticle -Database ReplDb -Name $article -Publication $pubName
                $art | Should -Not -BeNullOrEmpty
                $art.PublicationName | Should -Be $pubName
                $art.Name | Should -Be $article
            }
        }

        Context "Get-DbaReplArticle works" {
            BeforeAll {
                # we need some articles too get
                $article = 'ReplicateMe'
                $article2 = 'ReplicateMeToo'

                # we need some publications too
                $pubName = 'TestTrans'
                if (-not (Get-DbaReplPublication -Name $pubName -Type Transactional)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Transactional -PublicationName $pubName
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubName -Name $article)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubName -Name $article
                }

                $pubName = 'TestSnap'
                if (-not (Get-DbaReplPublication -Name $pubName -Type Snapshot)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -PublicationName $pubName
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article2
                }

                $pubName = 'TestMerge'
                if (-not (Get-DbaReplPublication -Name $pubName -Type Merge)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Merge -PublicationName $pubName
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article
                }
            }

            It "Get-DbaReplArticle gets all the articles from a server" {
                $getArt = Get-DbaReplArticle
                $getArt | Should -Not -BeNullOrEmpty
                $getArt | ForEach-Object { $_.SqlInstance | Should -Be 'mssql1' }
            }

            It "Get-DbaReplArticle gets all the articles from a particular database on a server" {
                $getArt = Get-DbaReplArticle -Database ReplDb
                $getArt | Should -Not -BeNullOrEmpty
                $getArt | ForEach-Object { $_.SqlInstance | Should -Be 'mssql1' }
                $getArt | ForEach-Object { $_.DatabaseName | Should -Be 'ReplDb' }
            }

            It "Get-DbaReplArticle gets all the articles from a specific publication" {
                $pubName = 'TestSnap'
                $arts = $article, $article2

                $getArt = Get-DbaReplArticle -Database ReplDb -Publication $pubName
                $getArt.Count | Should -Be 2
                $getArt.Name | Should -Be $arts
                $getArt | Foreach-Object {$_.PublicationName | Should -Be $pubName }
            }

            It "Get-DbaReplArticle gets a certain article from a specific publication" {
                $pubName = 'TestTrans'
                $Name = "ReplicateMe"

                $getArt = Get-DbaReplArticle -Database ReplDb -Publication $pubName -Name $Name
                $getArt.Count | Should -Be 1
                $getArt.Name | Should -Be $Name
                $getArt.PublicationName | Should -Be $pubName
            }

            It "Piping from Connect-DbaInstance works" -skip {
                Connect-DbaInstance -Database ReplDb | Get-DbaReplArticle | Should -Not -BeNullOrEmpty
            }

        }

        Context "Remove-DbaReplArticle works" {
            BeforeAll {
                # we need some articles too remove
                $article = 'ReplicateMe'

                # we need some publications with articles too
                $pubname = 'TestTrans'
                if (-not (Get-DbaReplPublication -Name $pubname -Type Transactional)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Transactional -PublicationName $pubname
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article
                }

                $pubname = 'TestSnap'
                if (-not (Get-DbaReplPublication -Name $pubname -Type Snapshot)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -PublicationName $pubname
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article
                }

                $pubname = 'TestMerge'
                if (-not (Get-DbaReplPublication -Name $pubname -Type Merge)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Merge -PublicationName $pubname
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article
                }

            }

            It "Remove-DbaReplArticle removes an article from a Transactional publication" {
                $pubname = 'TestTrans'
                $Name = "ReplicateMe"
                $rm = Remove-DbaReplArticle -Database ReplDb -Publication $pubname -Name $Name
                $rm.IsRemoved | Should -Be $true
                $rm.Status | Should -Be 'Removed'
                $article = Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $Name
                $article | Should -BeNullOrEmpty
            }

            It "Remove-DbaReplArticle removes an article from a Snapshot publication" {
                $pubname = 'TestSnap'
                $Name = "ReplicateMe"
                $rm = Remove-DbaReplArticle -Database ReplDb -Publication $pubname -Name $Name
                $rm.IsRemoved | Should -Be $true
                $rm.Status | Should -Be 'Removed'
                $article = Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $Name
                $article | Should -BeNullOrEmpty
            }

            It "Remove-DbaReplArticle removes an article from a Merge publication" {
                $pubname = 'TestMerge'
                $Name = "ReplicateMe"
                $rm = Remove-DbaReplArticle -Database ReplDb -Publication $pubname -Name $Name
                $rm.IsRemoved | Should -Be $true
                $rm.Status | Should -Be 'Removed'
                $article = Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $Name
                $article | Should -BeNullOrEmpty
            }
        }

        Context "Remove-DbaReplArticle works with piping" {
            BeforeAll {
                # we need some articles too remove
                $article = 'ReplicateMe'

                # we need some publications with articles too
                $pubname = 'TestTrans'
                if (-not (Get-DbaReplPublication -Name $pubname -Type Transactional)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Transactional -PublicationName $Name
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article
                }
            }

            It "Remove-DbaReplArticle removes an article from a Transactional publication" {
                $PublicationName = 'TestTrans'
                $Name = "ReplicateMe"

                $rm = Get-DbaReplArticle -Database ReplDb -Publication $PublicationName -Name $Name | Remove-DbaReplArticle -Confirm:$false
                $rm.IsRemoved | ForEach-Object { $_ | Should -Be $true }
                $rm.Status | ForEach-Object { $_ | Should -Be 'Removed' }
                $article = Get-DbaReplArticle -Database ReplDb  -Publication $PublicationName -Name $Name
                $article | Should -BeNullOrEmpty
            }
        }
    }
    Describe "Article Column commands" {
        BeforeAll {
            # if replication is disabled - enable it
            if (-not (Get-DbaReplDistributor).IsDistributor) {
                Enable-DbaReplDistributor
            }
            # if publishing is disabled - enable it
            if (-not (Get-DbaReplServer).IsPublisher) {
                Enable-DbaReplPublishing -PublisherSqlLogin $cred -EnableException
            }
            $article = 'ReplicateMe'

            # we need some publications with articles too
            $pubname = 'TestTrans'
            if (-not (Get-DbaReplPublication -Name $pubname -Type Transactional)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Transactional -PublicationName $pubname
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article
            }

            $pubname = 'TestSnap'
            if (-not (Get-DbaReplPublication -Name $pubname -Type Snapshot)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -PublicationName $pubname
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article
            }

            $pubname = 'TestMerge'
            if (-not (Get-DbaReplPublication -Name $pubname -Type Merge)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Merge -PublicationName $pubname
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article
            }
        }

        Context "Get-DbaReplArticleColumn works" {
            It "Gets all column information for a server" {
                $cols = Get-DbaReplArticleColumn
                $cols | Should -Not -BeNullOrEmpty
                $cols.SqlInstance | ForEach-Object { $_ | Should -Be 'mssql1' }
            }

            It "Gets all column information for specific database on a server" {
                $cols = Get-DbaReplArticleColumn -Database ReplDb
                $cols | Should -Not -BeNullOrEmpty
                $cols.SqlInstance | ForEach-Object { $_ | Should -Be 'mssql1' }
                $cols.DatabaseName | ForEach-Object { $_ | Should -Be 'ReplDb' }
            }

            It "Gets all column information for specific publication on a server" {
                $pubname = 'TestTrans'
                $cols = Get-DbaReplArticleColumn -Publication $pubname
                $cols | Should -Not -BeNullOrEmpty
                $cols.SqlInstance | ForEach-Object { $_ | Should -Be 'mssql1' }
                $cols.PublicationName | ForEach-Object { $_ | Should -Be $pubname }
            }

            It "Gets all column information for specific article on a server" {
                $pubname = 'TestTrans'
                $cols = Get-DbaReplArticleColumn -Publication $pubname -Article $article
                $cols | Should -Not -BeNullOrEmpty
                $cols.SqlInstance | ForEach-Object { $_ | Should -Be 'mssql1' }
                $cols.ArticleName | ForEach-Object { $_ | Should -Be $article }
            }

            It "Gets all column information for specific column on a server" {
                $pubname = 'TestTrans'
                $cols = Get-DbaReplArticleColumn -Publication $pubname -Column 'col1'
                $cols | Should -Not -BeNullOrEmpty
                $cols.SqlInstance | ForEach-Object { $_ | Should -Be 'mssql1' }
                $cols.ColumnName | ForEach-Object { $_ | Should -Be 'col1' }
            }
        }
    }

    Describe "Subscription commands" {
        BeforeAll {
            # if replication is disabled - enable it
            if (-not (Get-DbaReplDistributor).IsDistributor) {
                Enable-DbaReplDistributor
            }
            # if publishing is disabled - enable it
            if (-not (Get-DbaReplServer).IsPublisher) {
                Enable-DbaReplPublishing -PublisherSqlLogin $cred -EnableException
            }
            $article = 'ReplicateMe'

            # we need some publications with articles too
            $pubname = 'TestTrans'
            if (-not (Get-DbaReplPublication -Name $pubname -Type Transactional)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Transactional -PublicationName $pubname
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article
            }

            $pubname = 'TestSnap'
            if (-not (Get-DbaReplPublication -Name $pubname -Type Snapshot)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -PublicationName $pubname
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article
            }

            $pubname = 'TestMerge'
            if (-not (Get-DbaReplPublication -Name $pubname -Type Merge)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Merge -PublicationName $pubname
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $article
            }
        }

        Context "New-DbaReplSubscription works"  -tag test -skip {
            It "Adds a subscription" {
                { New-DbaReplPublication -SqlInstance 'mssql2' -Database ReplDb -PublicationDatabase ReplDb -PublicationName $pubname -Type 'Push' -EnableException } | Should -Not -Throw

                #TODO: waiting on get-dbareplsubscription to be implemented
            }
        }

        Context "Remove-DbaReplSubscription works" -tag test -skip{
            BeforeEach {
                #TODO: check it doesn't exist with get-dbareplsubscription
                New-DbaReplPublication -SqlInstance 'mssql2' -Database ReplDb -PublicationDatabase ReplDb -PublicationName $pubname -Type 'Push'
            }
            It "Removes a subscription" {
                { Remove-DbaReplPublication -SqlInstance 'mssql2' -Database ReplDb -PublicationDatabase ReplDb -PublicationName $pubname -EnableException } | Should -Not -Throw

                #TODO: waiting on get-dbareplsubscription to be implemented
            }
        }

    }
}
