Describe "Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sqladmin", $password

        $PSDefaultParameterValues["*:SqlInstance"] = "localhost"
        $PSDefaultParameterValues["*:SqlCredential"] = $cred
        $PSDefaultParameterValues["*:Confirm"] = $false
        $PSDefaultParameterValues["*:SharedPath"] = "/shared"
        $PSDefaultParameterValues["*:WarningAction"] = "SilentlyContinue"
        $global:ProgressPreference = "SilentlyContinue"

        #$null = Get-XPlatVariable | Where-Object { $PSItem -notmatch "Copy-", "Migration" } | Sort-Object
        # load dbatools-lib
        #Import-Module dbatools-core-library
        Import-Module ./dbatools.psd1 -Force

        $null = New-DbaDatabase -Name ReplDb
        $null = Invoke-DbaQuery -Database ReplDb -Query 'CREATE TABLE ReplicateMe ( id int identity (1,1) PRIMARY KEY, col1 varchar(10) )'

    }

    Describe "Enable\Disable Functions" -Tag ReplSetup {

        Context "Get-DbaReplDistributor works" {
            BeforeAll {

                # if distribution is enabled, disable it & enable it with defaults
                if ((Get-DbaReplDistributor).IsDistributor) {
                    Disable-DbaReplDistributor
                }
                Enable-DbaReplDistributor
            }

            It "gets a distributor" {
                (Get-DbaReplDistributor).IsDistributor | Should -Be $true
            }

            It "distribution database name is correct" {
                (Get-DbaReplDistributor).DistributionDatabases.Name | Should -Be 'distribution'
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
                Enable-DbaReplPublishing -SqlInstance localhost -EnableException
                (Get-DbaReplServer).IsPublisher | Should -Be $true
                'test' | Write-Warning
                Get-DbatoolsError | Out-String | Write-Warning
            }
        }

        Context "Disable-DbaReplPublishing works" {
            BeforeAll {

                write-output -Message ('I am a distributor {0}' -f (Get-DbaReplServer).IsDistributor)
                write-output -Message ('I am a publisher {0}' -f (Get-DbaReplServer).IsPublisher)

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

                write-output -Message ('I am a distributor {0}' -f (Get-DbaReplServer).IsDistributor)
                write-output -Message ('I am a publisher {0}' -f (Get-DbaReplServer).IsPublisher)
            }

            It "publishing starts enabled" {
                (Get-DbaReplServer).IsPublisher | Should -Be $true
            }

            It "publishing is disabled" {
                Disable-DbaReplPublishing -EnableException
                (Get-DbaReplServer).IsPublisher | Should -Be $false
            }
        }
    }

    Describe "RestofTests" -Tag "Rest" -Skip {

        Context "Get-DbaReplPublisher works" -skip {
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

        Context "New-DbaReplPublication works" -Tag test {
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
                New-DbaReplPublication -Database ReplDb -Type Transactional -PublicationName $Name
                (Get-DbaReplPublication -Name $Name) | Should -Not -BeNullOrEmpty
                (Get-DbaReplPublication -Name $Name).Database | Should -Be 'ReplDb'
                (Get-DbaReplPublication -Name $Name).Type | Should -Be 'Transactional'
            }
            It "New-DbaReplPublication creates a Snapshot publication" {
                $name = 'Snappy'
                New-DbaReplPublication -Database ReplDb -Type Snapshot -PublicationName $name
                (Get-DbaReplPublication -Name $name) | Should -Not -BeNullOrEmpty
                (Get-DbaReplPublication -Name $name).Database | Should -Be 'ReplDb'
                (Get-DbaReplPublication -Name $name).Type | Should -Be 'Snapshot'
            }
            It "New-DbaReplPublication creates a Merge publication" {
                $name = 'Mergey'
                New-DbaReplPublication -Database ReplDb -Type Merge -PublicationName $name
                (Get-DbaReplPublication -Name $name) | Should -Not -BeNullOrEmpty
                (Get-DbaReplPublication -Name $name).Database | Should -Be 'ReplDb'
                (Get-DbaReplPublication -Name $name).Type | Should -Be 'Merge'
            }

        }

        Context "Add-DbaReplArticle works" -Tag test {
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

                #$article =
            }

            It "Add-DbaReplArticle adds an article to a Transactional publication" {
                $pubname = 'TestPub'
                Add-DbaReplArticle -Database ReplDb -Type Transactional -PublicationName $Name
                (Get-DbaReplPublication -Name $Name) | Should -Not -BeNullOrEmpty
                (Get-DbaReplPublication -Name $Name).Database | Should -Be 'ReplDb'
                (Get-DbaReplPublication -Name $Name).Type | Should -Be 'Transactional'
            }
            It "New-DbaReplPublication creates a Snapshot publication" {
                $name = 'Snappy'
                New-DbaReplPublication -Database ReplDb -Type Snapshot -PublicationName $name
                (Get-DbaReplPublication -Name $name) | Should -Not -BeNullOrEmpty
                (Get-DbaReplPublication -Name $name).Database | Should -Be 'ReplDb'
                (Get-DbaReplPublication -Name $name).Type | Should -Be 'Snapshot'
            }
            It "New-DbaReplPublication creates a Merge publication" {
                $name = 'Mergey'
                New-DbaReplPublication -Database ReplDb -Type Merge -PublicationName $name
                (Get-DbaReplPublication -Name $name) | Should -Not -BeNullOrEmpty
                (Get-DbaReplPublication -Name $name).Database | Should -Be 'ReplDb'
                (Get-DbaReplPublication -Name $name).Type | Should -Be 'Merge'
            }

        }

        Context "Add-DbaReplArticle works" {
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

            It "distribution starts enabled" {
                (Get-DbaReplDistributor).IsDistributor | Should -Be $true
            }

            It "distribution is disabled" {
                Disable-DbaReplDistributor
                (Get-DbaReplDistributor).IsDistributor | Should -Be $false
            }
        }
    }
}
