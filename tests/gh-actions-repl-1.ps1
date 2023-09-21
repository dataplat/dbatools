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

    Describe "General commands" -Tag general {

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

    Describe "Publishing\Distribution commands" -tag pub  {

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

    Describe "Publication commands" -tag pub {

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
                { Remove-DbaReplPublication -Name $name -EnableException } | Should -Not -Throw
                (Get-DbaReplPublication -Name $name) | Should -BeNullOrEmpty
            }

            It "Remove-DbaReplPublication removes a publication that has no articles" {
                $name = 'TestSnap'
                { Remove-DbaReplPublication -Name $name -EnableException } | Should -Not -Throw
                (Get-DbaReplPublication -Name $name) | Should -BeNullOrEmpty
            }

        }
    }
}
