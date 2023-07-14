Describe "Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sqladmin", $password

        $PSDefaultParameterValues["*:SqlInstance"] = "mssql1"
        $PSDefaultParameterValues["*:SqlCredential"] = $cred
        $PSDefaultParameterValues["*:SubscriptionSqlCredential1"] = $cred
        $PSDefaultParameterValues["*:Confirm"] = $false
        $PSDefaultParameterValues["*:SharedPath"] = "/shared"
        $PSDefaultParameterValues["*:WarningAction"] = "SilentlyContinue"
        $global:ProgressPreference = "SilentlyContinue"

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
                New-DbaReplPublication -Database ReplDb -Type Transactional -Name ('{0}-Trans' -f $Name)
                New-DbaReplPublication -Database ReplDb -Type Merge -Name ('{0}-Merge' -f $Name)
                $null = New-DbaDatabase -Name Test
                New-DbaReplPublication -Database Test -Type Snapshot -Name ('{0}-Snapshot' -f $Name)
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
                { New-DbaReplPublication -Database ReplDb -Type Transactional -Name $Name -EnableException } | Should -Not -Throw
                (Get-DbaReplPublication -Name $Name) | Should -Not -BeNullOrEmpty
                (Get-DbaReplPublication -Name $Name).DatabaseName | Should -Be 'ReplDb'
                (Get-DbaReplPublication -Name $Name).Type | Should -Be 'Transactional'
            }
            It "New-DbaReplPublication creates a Snapshot publication" {
                $name = 'Snappy'
                { New-DbaReplPublication -Database ReplDb -Type Snapshot -Name $name -EnableException } | Should -Not -Throw
                (Get-DbaReplPublication -Name $name) | Should -Not -BeNullOrEmpty
                (Get-DbaReplPublication -Name $name).DatabaseName | Should -Be 'ReplDb'
                (Get-DbaReplPublication -Name $name).Type | Should -Be 'Snapshot'
            }
            It "New-DbaReplPublication creates a Merge publication" {
                $name = 'Mergey'
                { New-DbaReplPublication -Database ReplDb -Type Merge -Name $name -EnableException } | Should -Not -Throw
                (Get-DbaReplPublication -Name $name) | Should -Not -BeNullOrEmpty
                (Get-DbaReplPublication -Name $name).DatabaseName | Should -Be 'ReplDb'
                (Get-DbaReplPublication -Name $name).Type | Should -Be 'Merge'
            }
        }

        Context "Remove-DbaReplPublication works" {
            BeforeAll {
                # if replication is disabled - enable it
                if (-not (Get-DbaReplDistributor).IsDistributor) {
                    Enable-DbaReplDistributor
                }
                # if publishing is disabled - enable it
                if (-not (Get-DbaReplServer).IsPublisher) {
                    Enable-DbaReplPublishing -PublisherSqlLogin $cred -EnableException
                }
                $articleName = 'ReplicateMe'

                # we need some publications too
                $pubName = 'TestTrans'
                if (-not (Get-DbaReplPublication -Name $pubName -Type Transactional)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Transactional -Name $pubName
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubName -Name $articleName)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubName -Name $articleName
                }

                $pubName = 'TestSnap'
                if (-not (Get-DbaReplPublication -Name $pubName -Type Snapshot)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -Name $pubName
                }
                $pubName = 'TestMerge'
                if (-not (Get-DbaReplPublication -Name $pubName -Type Merge)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Merge -Name $pubName
                }
            }

            It "Remove-DbaReplPublication removes a publication that has articles" {
                $name = 'TestTrans'
                { Remove-DbaReplPublication -Name $name -EnableException -Force } | Should -Not -Throw
                (Get-DbaReplPublication -Name $name) | Should -BeNullOrEmpty
            }

            It "Remove-DbaReplPublication removes a publication that has no articles" {
                $name = 'TestSnap'
                { Remove-DbaReplPublication -Name $name -EnableException } | Should -Not -Throw
                (Get-DbaReplPublication -Name $name) | Should -BeNullOrEmpty
            }

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
                $null = New-DbaReplPublication -Database ReplDb -Type Transactional -Name $Name
            }
            $name = 'TestSnap'
            if (-not (Get-DbaReplPublication -Name $name -Type Snapshot)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -Name $Name
            }
            $name = 'TestMerge'
            if (-not (Get-DbaReplPublication -Name $name -Type Merge)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Merge -Name $Name
            }
            $articleName = 'ReplicateMe'
            $articleName2 = 'ReplicateMeToo'
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
                { Add-DbaReplArticle -Database ReplDb -Name $articleName -Publication $pubName -EnableException } | Should -not -throw
                $art = Get-DbaReplArticle -Database ReplDb -Name $articleName -Publication $pubName
                $art | Should -Not -BeNullOrEmpty
                $art.PublicationName | Should -Be $pubName
                $art.Name | Should -Be $articleName
            }

            It "Add-DbaReplArticle adds an article to a Snapshot publication and specifies create script options" {
                $pubname = 'TestPub'
                $cso = New-DbaReplCreationScriptOptions -Options NonClusteredIndexes, Statistics
                { Add-DbaReplArticle -Database ReplDb -Name $articleName2 -Publication $pubname -CreationScriptOptions $cso -EnableException } | Should -not -throw
                $art = Get-DbaReplArticle -Database ReplDb -Name $articleName2 -Publication $pubName
                $art | Should -Not -BeNullOrEmpty
                $art.PublicationName | Should -Be $pubName
                $art.Name | Should -Be $articleName2
            }

            It "Add-DbaReplArticle adds an article to a Snapshot publication" {
                $pubname = 'TestSnap'
                { Add-DbaReplArticle -Database ReplDb -Name $articleName -Publication $pubname -EnableException } | Should -not -throw
                $art = Get-DbaReplArticle -Database ReplDb -Name $articleName -Publication $pubName
                $art | Should -Not -BeNullOrEmpty
                $art.PublicationName | Should -Be $pubName
                $art.Name | Should -Be $articleName
            }

            It "Add-DbaReplArticle adds an article to a Snapshot publication with a filter" {
                $pubName = 'TestSnap'
                { Add-DbaReplArticle -Database ReplDb -Name $articleName2 -Publication $pubName -Filter "col1 = 'test'" -EnableException } | Should -not -throw
                $art = Get-DbaReplArticle -Database ReplDb -Name $articleName2 -Publication $pubName
                $art | Should -Not -BeNullOrEmpty
                $art.PublicationName | Should -Be $pubName
                $art.Name | Should -Be $articleName2
                $art.FilterClause | Should -Be "col1 = 'test'"
            }

            It "Add-DbaReplArticle adds an article to a Merge publication" {
                $pubname = 'TestMerge'
                { Add-DbaReplArticle -Database ReplDb -Name $articleName -Publication $pubname -EnableException } | Should -not -throw
                $art = Get-DbaReplArticle -Database ReplDb -Name $articleName -Publication $pubName
                $art | Should -Not -BeNullOrEmpty
                $art.PublicationName | Should -Be $pubName
                $art.Name | Should -Be $articleName
            }
        }

        Context "Get-DbaReplArticle works" {
            BeforeAll {
                # we need some articles too get
                $articleName = 'ReplicateMe'
                $articleName2 = 'ReplicateMeToo'

                # we need some publications too
                $pubName = 'TestTrans'
                if (-not (Get-DbaReplPublication -Name $pubName -Type Transactional)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Transactional -Name $pubName
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubName -Name $articleName)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubName -Name $articleName
                }

                $pubName = 'TestSnap'
                if (-not (Get-DbaReplPublication -Name $pubName -Type Snapshot)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -Name $pubName
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName2
                }

                $pubName = 'TestMerge'
                if (-not (Get-DbaReplPublication -Name $pubName -Type Merge)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Merge -Name $pubName
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName
                }
            }

            It "Get-DbaReplArticle gets all the articles from a server" {
                $getArt = Get-DbaReplArticle
                $getArt | Should -Not -BeNullOrEmpty
                $getArt | ForEach-Object { $_.SqlInstance.name | Should -Be 'mssql1' }
            }

            It "Get-DbaReplArticle gets all the articles from a particular database on a server" {
                $getArt = Get-DbaReplArticle -Database ReplDb
                $getArt | Should -Not -BeNullOrEmpty
                $getArt | ForEach-Object { $_.SqlInstance.Name | Should -Be 'mssql1' }
                $getArt | ForEach-Object { $_.DatabaseName | Should -Be 'ReplDb' }
            }

            It "Get-DbaReplArticle gets all the articles from a specific publication" {
                $pubName = 'TestSnap'
                $arts = $articleName, $articleName2

                $getArt = Get-DbaReplArticle -Database ReplDb -Publication $pubName
                $getArt.Count | Should -Be 2
                $getArt.Name | Should -Be $arts
                $getArt | Foreach-Object { $_.PublicationName | Should -Be $pubName }
            }

            It "Get-DbaReplArticle gets a certain article from a specific publication" {
                $pubName = 'TestTrans'

                $getArt = Get-DbaReplArticle -Database ReplDb -Publication $pubName -Name $articleName
                $getArt.Count | Should -Be 1
                $getArt.Name | Should -Be $ArticleName
                $getArt.PublicationName | Should -Be $pubName
            }
        }

        Context "Remove-DbaReplArticle works" {
            BeforeAll {
                # we need some articles too remove
                $articleName = 'ReplicateMe'

                # we need some publications with articles too
                $pubname = 'TestTrans'
                if (-not (Get-DbaReplPublication -Name $pubname -Type Transactional)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Transactional -Name $pubname
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName
                }

                $pubname = 'TestSnap'
                if (-not (Get-DbaReplPublication -Name $pubname -Type Snapshot)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -Name $pubname
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName
                }

                $pubname = 'TestMerge'
                if (-not (Get-DbaReplPublication -Name $pubname -Type Merge)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Merge -Name $pubname
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName
                }

            }

            It "Remove-DbaReplArticle removes an article from a Transactional publication" {
                $pubname = 'TestTrans'
                $Name = "ReplicateMe"
                $rm = Remove-DbaReplArticle -Database ReplDb -Publication $pubname -Name $Name
                $rm.IsRemoved | Should -Be $true
                $rm.Status | Should -Be 'Removed'
                $articleName = Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $Name
                $articleName | Should -BeNullOrEmpty
            }

            It "Remove-DbaReplArticle removes an article from a Snapshot publication" {
                $pubname = 'TestSnap'
                $Name = "ReplicateMe"
                $rm = Remove-DbaReplArticle -Database ReplDb -Publication $pubname -Name $Name
                $rm.IsRemoved | Should -Be $true
                $rm.Status | Should -Be 'Removed'
                $articleName = Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $Name
                $articleName | Should -BeNullOrEmpty
            }

            It "Remove-DbaReplArticle removes an article from a Merge publication" {
                $pubname = 'TestMerge'
                $Name = "ReplicateMe"
                $rm = Remove-DbaReplArticle -Database ReplDb -Publication $pubname -Name $Name
                $rm.IsRemoved | Should -Be $true
                $rm.Status | Should -Be 'Removed'
                $articleName = Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $Name
                $articleName | Should -BeNullOrEmpty
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
            $articleName = 'ReplicateMe'

            # we need some publications with articles too
            $pubname = 'TestTrans'
            if (-not (Get-DbaReplPublication -Name $pubname -Type Transactional)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Transactional -Name $pubname
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName
            }

            $pubname = 'TestSnap'
            if (-not (Get-DbaReplPublication -Name $pubname -Type Snapshot)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -Name $pubname
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName
            }

            $pubname = 'TestMerge'
            if (-not (Get-DbaReplPublication -Name $pubname -Type Merge)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Merge -Name $pubname
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName
            }
        }

        Context "Get-DbaReplArticleColumn works" {
            It "Gets all column information for a server" {
                $cols = Get-DbaReplArticleColumn
                $cols | Should -Not -BeNullOrEmpty
                $cols.SqlInstance | ForEach-Object { $_.Name | Should -Be 'mssql1' }
            }

            It "Gets all column information for specific database on a server" {
                $cols = Get-DbaReplArticleColumn -Database ReplDb
                $cols | Should -Not -BeNullOrEmpty
                $cols.SqlInstance | ForEach-Object { $_.Name | Should -Be 'mssql1' }
                $cols.DatabaseName | ForEach-Object { $_ | Should -Be 'ReplDb' }
            }

            It "Gets all column information for specific publication on a server" {
                $pubname = 'TestTrans'
                $cols = Get-DbaReplArticleColumn -Publication $pubname
                $cols | Should -Not -BeNullOrEmpty
                $cols.SqlInstance | ForEach-Object { $_.Name | Should -Be 'mssql1' }
                $cols.PublicationName | ForEach-Object { $_ | Should -Be $pubname }
            }

            It "Gets all column information for specific article on a server" {
                $pubname = 'TestTrans'
                $cols = Get-DbaReplArticleColumn -Publication $pubname -Article $articleName
                $cols | Should -Not -BeNullOrEmpty
                $cols.SqlInstance | ForEach-Object { $_.Name | Should -Be 'mssql1' }
                $cols.ArticleName | ForEach-Object { $_ | Should -Be $articleName }
            }

            It "Gets all column information for specific column on a server" {
                $pubname = 'TestTrans'
                $cols = Get-DbaReplArticleColumn -Publication $pubname -Column 'col1'
                $cols | Should -Not -BeNullOrEmpty
                $cols.SqlInstance | ForEach-Object { $_.Name | Should -Be 'mssql1' }
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
            $articleName = 'ReplicateMe'

            # we need some publications with articles too
            $pubname = 'TestTrans'
            if (-not (Get-DbaReplPublication -Name $pubname -Type Transactional)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Transactional -Name $pubname
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName
            }

            $pubname = 'TestSnap'
            if (-not (Get-DbaReplPublication -Name $pubname -Type Snapshot)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -Name $pubname
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName
            }

            $pubname = 'TestMerge'
            if (-not (Get-DbaReplPublication -Name $pubname -Type Merge)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Merge -Name $pubname
            }
        }

        Context "New-DbaReplSubscription works"  -tag sub {
            BeforeAll {
                if (Get-DbaReplSubscription -SqlInstance mssql1 -Name TestTrans -Database ReplDb -SubscriberName mssql2 -SubscriptionDatabase ReplDbTrans) {
                    Remove-DbaReplSubscription -SqlInstance mssql2 -SubscriptionDatabase ReplDbTrans -PublisherSqlInstance mssql1  -PublicationDatabase ReplDb -PublicationName TestTrans -Confirm:$false -EnableException
                }
                if (Get-DbaReplSubscription -SqlInstance mssql1 -Name TestSnap -Database ReplDb -SubscriberName mssql2 -SubscriptionDatabase ReplDbSnap) {
                    Remove-DbaReplSubscription -SqlInstance mssql2 -SubscriptionDatabase ReplDbSnap -PublisherSqlInstance mssql1  -PublicationDatabase ReplDb -PublicationName TestSnap -Confirm:$false -EnableException
                }
            }
            It "Adds a subscription" {
                #TODO: we are here and broke
                $pubName = 'TestTrans'
                #transactional
                { New-DbaReplSubscription -SqlInstance mssql2 -Database ReplDbTrans -PublisherSqlInstance mssql1 -PublicationDatabase ReplDb -PublicationName $pubName -Type Push -EnableException } | Should -Not -Throw

                $sub = Get-DbaReplSubscription -SqlInstance mssql1 -Name $pubname
                $sub | Should -Not -BeNullOrEmpty
                $sub.SqlInstance | ForEach-Object { $_ | Should -Be 'mssql1' }
                $sub.SubscriberName | ForEach-Object { $_ | Should -Be 'mssql2' }
                $sub.PublicationName | ForEach-Object { $_ | Should -Be $pubname }
                $sub.SubscriptionType | ForEach-Object { $_ | Should -Be 'Push' }
            }

            It "Adds a pull subscription" -tag sub {
                $pubName = 'TestSnap'
                { New-DbaReplSubscription -SqlInstance mssql2 -Database ReplDbSnap -PublisherSqlInstance mssql1 -PublicationDatabase ReplDb -PublicationName $pubName -Type Pull -EnableException } | Should -Not -Throw

                $sub = Get-DbaReplSubscription -SqlInstance mssql1 -Name $pubname
                $sub | Should -Not -BeNullOrEmpty
                $sub.SqlInstance | ForEach-Object { $_ | Should -Be 'mssql1' }
                $sub.SubscriberName | ForEach-Object { $_ | Should -Be 'mssql2' }
                $sub.PublicationName | ForEach-Object { $_ | Should -Be $pubname }
                $sub.SubscriptionType | ForEach-Object { $_ | Should -Be 'Pull' }
            }

            It "Throws an error if there are no articles in the publication" {
                $pubName = 'TestMerge'
                { New-DbaReplSubscription -SqlInstance mssql2 -Database ReplDb -PublisherSqlInstance mssql1 -PublicationDatabase ReplDb -PublicationName $pubName -Type Pull -EnableException } | Should -Throw
            }
        }

        Context "Remove-DbaReplSubscription works"{
            BeforeEach {
                $pubName = 'TestTrans'
                if (-not (Get-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriptionDatabase ReplDb -Name $pubname -Type Push | Where-Object SubscriberName -eq mssql2)) {
                    New-DbaReplSubscription -SqlInstance mssql2 -Database ReplDb -PublisherSqlInstance mssql1 -PublicationDatabase ReplDb -PublicationName $pubname -Type Push
                }
            }
            It "Removes a subscription" {
                Get-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriptionDatabase ReplDb -Name $pubname -Type Push | Should -Not -BeNullOrEmpty
                { Remove-DbaReplSubscription -SqlInstance mssql2 -SubscriptionDatabase ReplDb -PublisherSqlInstance mssql1  -PublicationDatabase ReplDb -PublicationName $pubname -EnableException } | Should -Not -Throw
                Get-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriptionDatabase ReplDb -Name $pubname -Type Push | Where-Object SubscriberName -eq mssql2 | Should -BeNullOrEmpty
            }
        }


        Context "Get-DbaReplSubscription works" {
            BeforeAll {
                $pubName = 'TestTrans'
                if (-not (Get-DbaReplSubscription -Name $pubname -Type Push | Where-Object SubscriberName -eq mssql2)) {
                    New-DbaReplSubscription -SqlInstance mssql2 -Database ReplDb -PublisherSqlInstance mssql1 -PublicationDatabase ReplDb -PublicationName $pubname -Type Push -enableException
                }
                $pubName = 'TestSnap'
                if (-not (Get-DbaReplSubscription -Name $pubname -Type Push | Where-Object SubscriberName -eq mssql2)) {
                    New-DbaReplSubscription -SqlInstance mssql2 -Database ReplDb -PublisherSqlInstance mssql1 -PublicationDatabase ReplDb -PublicationName $pubname -Type Push -enableException
                }
            }

            It "Gets subscriptions" {
                $sub = Get-DbaReplSubscription -SqlInstance mssql1
                $sub | Should -Not -BeNullOrEmpty
                $sub.SqlInstance | ForEach-Object { $_ | Should -Be 'mssql1' }
            }

            It "Gets subscriptions to a particular instance" {

            }

        }

    }

    Describe "Piping" {
        BeforeAll {
            # if replication is disabled - enable it
            if (-not (Get-DbaReplDistributor).IsDistributor) {
                Enable-DbaReplDistributor
            }
            # if publishing is disabled - enable it
            if (-not (Get-DbaReplServer).IsPublisher) {
                Enable-DbaReplPublishing -PublisherSqlLogin $cred -EnableException
            }

            # we need some articles too get
            $articleName = 'ReplicateMe'
            $articleName2 = 'ReplicateMeToo'

            # we need some publications too
            $pubName = 'TestTrans'
            if (-not (Get-DbaReplPublication -Name $pubName -Type Transactional)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Transactional -Name $pubName -EnableException
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubName -Name $articleName)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubName -Name $articleName -EnableException
            }

            $pubName = 'TestSnap'
            if (-not (Get-DbaReplPublication -Name $pubName -Type Snapshot)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -Name $pubName -EnableException
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName -EnableException
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName2 -EnableException
            }

            $pubName = 'TestMerge'
            if (-not (Get-DbaReplPublication -Name $pubName -Type Merge)) {
                $null = New-DbaReplPublication -Database ReplDb -Type Merge -Name $pubName -EnableException
            }
            if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName -EnableException
            }
            # piping doesn't work well if there are PSDefaultParameterValues set
            $PSDefaultParameterValues = $null
        }

        Context "Get-DbaReplPublisher works with piping" {
            It "gets a publisher using piping" {
                (Connect-DbaInstance -SqlInstance 'mssql1' -SqlCredential $cred  | Get-DbaReplPublisher).PublisherType | Should -Be "MSSQLSERVER"
            }
        }

        Context "Get-DbaReplPublication works with piping" {
            It "works with piping" {
                Connect-DbaInstance -SqlInstance 'mssql1' -SqlCredential $cred | Get-DbaReplPublication | Should -Not -BeNullOrEmpty
            }
        }

        Context "Get-DbaReplDistributor works with piping" {
            It "can pipe a sql server object to it" {
                Connect-DbaInstance -SqlInstance 'mssql1' -SqlCredential $cred | Get-DbaReplDistributor | Should -Not -BeNullOrEmpty
            }
        }

        Context "Get-DbaReplArticle works with piping" {
            It "Piping from Connect-DbaInstance to works" {
                Connect-DbaInstance -SqlInstance 'mssql1' -SqlCredential $cred -Database ReplDb | Get-DbaReplArticle | Should -Not -BeNullOrEmpty
            }
        }

        Context "Remove-DbaReplArticle works with piping" {
            It "Remove-DbaReplArticle removes an article from a Transactional publication" {
                $pubName = 'TestTrans'
                $Name = "ReplicateMe"

                $rm = Get-DbaReplArticle -SqlInstance 'mssql1' -SqlCredential $cred -Database ReplDb -Publication $pubName -Name $Name | Remove-DbaReplArticle -Confirm:$false
                $rm.IsRemoved | ForEach-Object { $_ | Should -Be $true }
                $rm.Status | ForEach-Object { $_ | Should -Be 'Removed' }
                $articleName = Get-DbaReplArticle  -SqlInstance 'mssql1' -SqlCredential $cred -Database ReplDb -Publication $pubName -Name $Name
                $articleName | Should -BeNullOrEmpty
            }
        }

        Context "Remove-DbaReplPublication works with piping" {
            It "Remove-DbaReplPublication removes a publication using piping" {
                $name = 'TestMerge'
                { Get-DbaReplPublication -SqlInstance 'mssql1' -SqlCredential $cred -Name $name -EnableException | Remove-DbaReplPublication -EnableException } | Should -Not -Throw
                (Get-DbaReplPublication -SqlInstance 'mssql1' -SqlCredential $cred -Name $name -EnableException) | Should -BeNullOrEmpty
            }
        }
    }
}
