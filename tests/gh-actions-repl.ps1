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
    }

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
            # if distribution is disabled - enable it
            if (-not (Get-DbaReplDistributor).IsDistributor) {
                Enable-DbaReplDistributor
            }
            # if Publishing is enabled - disable it
            if ((Get-DbaReplServer).IsPublisher) {
                Disable-DbaReplPublishing
            }
        }

        It "publishing starts disabled" {
            (Get-DbaReplServer).IsPublisher | Should -Be $false
        }

        It "publishing is enabled" {
            Enable-DbaReplPublishing -EnableException
            (Get-DbaReplServer).IsPublisher | Should -Be $true
        }
    }

    Context "Disable-DbaReplPublishing works" {
        BeforeAll {

            write-output -Message ('I am a distributor {0}' -f (Get-DbaReplServer).IsDistributor)
            write-output -Message ('I am a publisher {0}' -f (Get-DbaReplServer).IsPublisher)

            # if distribution is disabled - enable it
            if (-not (Get-DbaReplDistributor).IsDistributor) {
                write-output -message 'I should enable distribution'
                Enable-DbaReplDistributor -EnableException
            }

            # if publishing is disabled - enable it
            if (-not (Get-DbaReplServer).IsPublisher) {
                write-output -message 'I should enable publishing'
                Enable-DbaReplPublishing -EnableException
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
}
