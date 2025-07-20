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


    Describe "Subscription commands" -tag sub {
        BeforeAll {
            # if replication is disabled - enable it
            #if (-not (Get-DbaReplDistributor).IsDistributor) {
            #    Enable-DbaReplDistributor
            #}
            ## if publishing is disabled - enable it
            #if (-not (Get-DbaReplServer).IsPublisher) {
            #    Enable-DbaReplPublishing -PublisherSqlLogin $cred -EnableException
            #}
            #$articleName = 'ReplicateMe'

            <#
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
            #>
        }

        Context "New-DbaReplSubscription works" -skip {
            BeforeAll {
                if (Get-DbaReplSubscription -SqlInstance mssql1 -PublicationName TestTrans) {
                    (Get-DbaReplSubscription -SqlInstance mssql1 -PublicationName TestTrans).foreach{
                        Remove-DbaReplSubscription -SqlInstance $psitem.SqlInstance -SubscriptionDatabase $psitem.SubscriptionDBName -SubscriberSqlInstance $psitem.SubscriberName -Database $psitem.DatabaseName -PublicationName $psitem.PublicationName -Confirm:$false -EnableException
                    }
                }
                if (Get-DbaReplSubscription -SqlInstance mssql1 -PublicationName TestSnap) {
                    (Get-DbaReplSubscription -SqlInstance mssql1 -PublicationName TestSnap).foreach{
                        Remove-DbaReplSubscription -SqlInstance $psitem.SqlInstance -SubscriptionDatabase $psitem.SubscriptionDBName -SubscriberSqlInstance $psitem.SubscriberName -Database $psitem.DatabaseName -PublicationName $psitem.PublicationName -Confirm:$false -EnableException
                    }
                }
                Get-DbaReplArticle -Publication TestSnap | Remove-DbaReplArticle -Confirm:$false
            }
            It "Adds a subscription" {
                $pubName = 'TestTrans'
                { New-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriberSqlInstance mssql2 -SubscriptionDatabase ReplDbTrans -PublicationName $pubName -Type Push -EnableException } | Should -Not -Throw

                $sub = Get-DbaReplSubscription -SqlInstance mssql1 -PublicationName $pubname
                $sub | Should -Not -BeNullOrEmpty
                $sub.SqlInstance | ForEach-Object { $_ | Should -Be 'mssql1' }
                $sub.SubscriberName | ForEach-Object { $_ | Should -Be 'mssql2' }
                $sub.PublicationName | ForEach-Object { $_ | Should -Be $pubname }
                $sub.SubscriptionType | ForEach-Object { $_ | Should -Be 'Push' }
            }

            It "Adds a pull subscription" {
                #TODO: Fix pull subscriptions in New-DbaReplSubscription command
                $pubName = 'TestMerge'
                { New-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriberSqlInstance mssql2 -SubscriptionDatabase ReplDbSnap -PublicationName $pubName -Type Pull -EnableException } | Should -Not -Throw

                $sub = Get-DbaReplSubscription -SqlInstance mssql1 -PublicationName $pubname
                $sub | Should -Not -BeNullOrEmpty
                $sub.SqlInstance | ForEach-Object { $_ | Should -Be 'mssql1' }
                $sub.SubscriberName | ForEach-Object { $_ | Should -Be 'mssql2' }
                $sub.PublicationName | ForEach-Object { $_ | Should -Be $pubname }
                $sub.SubscriptionType | ForEach-Object { $_ | Should -Be 'Pull' }
            }

            It "Throws an error if there are no articles in the publication" {
                $pubName = 'TestSnap'
                { New-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriberSqlInstance mssql2 -SubscriptionDatabase ReplDb -PublicationName $pubName -Type Pull -EnableException } | Should -Throw
            }
        }

        Context "Remove-DbaReplSubscription works" -skip {
            BeforeEach {
                $pubName = 'TestTrans'
                if (-not (Get-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriptionDatabase ReplDb -PublicationName $pubname -Type Push | Where-Object SubscriberName -eq mssql2)) {
                    New-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriberSqlInstance mssql2 -SubscriptionDatabase ReplDb -PublicationName $pubname -Type Push
                }
            }
            It "Removes a push subscription" {
                Get-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriptionDatabase ReplDb -PublicationName $pubname -Type Push | Should -Not -BeNullOrEmpty
                { Remove-DbaReplSubscription -SqlInstance mssql1 -SubscriptionDatabase ReplDb -SubscriberSqlInstance mssql2  -Database ReplDb -PublicationName $pubname -EnableException } | Should -Not -Throw
                Get-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriptionDatabase ReplDb -PublicationName $pubname -Type Push | Where-Object SubscriberName -eq mssql2 | Should -BeNullOrEmpty
            }
            It "Removes a pull subscription" -skip {
                #TODO: Fix pull subscriptions in New-DbaReplSubscription command
                Get-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriptionDatabase ReplDb -PublicationName $pubname -Type Pull | Should -Not -BeNullOrEmpty
                { Remove-DbaReplSubscription -SqlInstance mssql1 -SubscriptionDatabase ReplDb -SubscriberSqlInstance mssql2  -Database ReplDb -PublicationName $pubname -EnableException } | Should -Not -Throw
                Get-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriptionDatabase ReplDb -PublicationName $pubname -Type Pull | Where-Object SubscriberName -eq mssql2 | Should -BeNullOrEmpty
            }
        }


        Context "Get-DbaReplSubscription works" {
            BeforeAll {
                $pubname = 'TestTrans'
                $articleName = 'ReplicateMe'
                if (-not (Get-DbaReplPublication -Name $pubname -Type Transactional)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Transactional -Name $pubname
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName
                }
                if (-not (Get-DbaReplSubscription -PublicationName $pubname -Type Push | Where-Object SubscriberName -eq mssql2)) {
                    New-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriberSqlInstance mssql2 -SubscriptionDatabase ReplDb -PublicationName $pubname -Type Push -enableException
                }

                $pubName = 'TestSnap'
                if (-not (Get-DbaReplPublication -Name $pubname -Type Snapshot)) {
                    $null = New-DbaReplPublication -Database ReplDb -Type Snapshot -Name $pubname
                }
                if (-not (Get-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName)) {
                    $null = Add-DbaReplArticle -Database ReplDb -Publication $pubname -Name $articleName
                }
                if (-not (Get-DbaReplSubscription -PublicationName $pubname -Type Push | Where-Object SubscriberName -eq mssql2)) {
                    New-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb -SubscriberSqlInstance mssql2 -SubscriptionDatabase ReplDb -PublicationName $pubname -Type Push -enableException
                }
            }

            It "Gets subscriptions" {
                $sub = Get-DbaReplSubscription -SqlInstance mssql1
                $sub | Should -Not -BeNullOrEmpty
                $sub.SqlInstance | ForEach-Object { $_ | Should -Be 'mssql1' }
            }

            It "Gets subscriptions for a particular database" {
                $sub = Get-DbaReplSubscription -SqlInstance mssql1 -Database ReplDb
                $sub | Should -Not -BeNullOrEmpty
                $sub.DatabaseName | ForEach-Object { $_ | Should -Be 'ReplDb' }
            }

            It "Gets subscriptions by publication name" {
                $sub = Get-DbaReplSubscription -SqlInstance mssql1 -PublicationName TestTrans
                $sub | Should -Not -BeNullOrEmpty
                $sub.PublicationName | ForEach-Object { $_ | Should -Be 'TestTrans' }
            }

            It "Gets subscriptions by type" {
                $sub = Get-DbaReplSubscription -SqlInstance mssql1 -Type Push
                $sub | Should -Not -BeNullOrEmpty
                $sub.SubscriptionType | ForEach-Object { $_ | Should -Be 'Push' }

                $sub = Get-DbaReplSubscription -SqlInstance mssql1 -Type Pull
                if($sub) {
                    $sub.SubscriptionType | ForEach-Object { $_ | Should -Be 'Pull' }
                }
            }

            It "Gets subscriptions by subscriber name" {
                $sub = Get-DbaReplSubscription -SqlInstance mssql1 -SubscriberName mssql2
                $sub | Should -Not -BeNullOrEmpty
                $sub.SubscriberName | ForEach-Object { $_ | Should -Be 'mssql2' }
            }

            It "Gets subscriptions by subscription database name" {
                $sub = Get-DbaReplSubscription -SqlInstance mssql1 -SubscriptionDatabase ReplDbTrans
                $sub | Should -Not -BeNullOrEmpty
                $sub.SubscriptionDBName | ForEach-Object { $_ | Should -Be 'ReplDbTrans' }
            }
        }
    }

    Describe "Piping" -tag pipe {
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
                { Get-DbaReplPublication -SqlInstance 'mssql1' -SqlCredential $cred -Name $name -EnableException | Remove-DbaReplPublication -Confirm:$false -EnableException } | Should -Not -Throw
                (Get-DbaReplPublication -SqlInstance 'mssql1' -SqlCredential $cred -Name $name -EnableException) | Should -BeNullOrEmpty
            }
        }
    }
}
