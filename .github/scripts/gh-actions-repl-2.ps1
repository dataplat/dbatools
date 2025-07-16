Describe "Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sqladmin", $password

        $PSDefaultParameterValues["*:SqlInstance"] = "mssql1"
        $PSDefaultParameterValues["*:SqlCredential"] = $cred
        $PSDefaultParameterValues["*:SubscriberSqlCredential"] = $cred
        $PSDefaultParameterValues["*:Confirm"] = $false
        $PSDefaultParameterValues["*:SharedPath"] = "/shared"
        $PSDefaultParameterValues["*:WarningAction"] = "SilentlyContinue"
        $global:ProgressPreference = "SilentlyContinue"

        Import-Module ./dbatools.psd1 -Force

        $null = New-DbaDatabase -Name ReplDb
        $null = Invoke-DbaQuery -Database ReplDb -Query 'CREATE TABLE ReplicateMe ( id int identity (1,1) PRIMARY KEY, col1 varchar(10) ); CREATE TABLE ReplicateMeToo ( id int identity (1,1) PRIMARY KEY, col1 varchar(10) );'
    }

    Describe "Article commands" -tag art {
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
                $pubName = 'TestTrans'
                { Add-DbaReplArticle -Database ReplDb -Name $articleName -Publication $pubName -EnableException } | Should -not -throw
                $art = Get-DbaReplArticle -Database ReplDb -Name $articleName -Publication $pubName
                $art | Should -Not -BeNullOrEmpty
                $art.PublicationName | Should -Be $pubName
                $art.Name | Should -Be $articleName
            }

            It "Add-DbaReplArticle adds an article to a Snapshot publication and specifies create script options" {
                $pubname = 'TestTrans'
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

    Describe "Article Column commands" -tag art {
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

}
