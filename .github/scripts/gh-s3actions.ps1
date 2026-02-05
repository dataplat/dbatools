Describe "S3 Backup Integration Tests" -Tag "IntegrationTests", "S3" {
    BeforeAll {
        $password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sa", $password

        $PSDefaultParameterValues["*:SqlInstance"] = "localhost"
        $PSDefaultParameterValues["*:SqlCredential"] = $cred
        $PSDefaultParameterValues["*:Confirm"] = $false
        $global:ProgressPreference = "SilentlyContinue"

        # S3 configuration from environment variables
        $script:S3Endpoint = $env:S3_ENDPOINT
        $script:S3Bucket = $env:S3_BUCKET
        $script:S3AccessKey = $env:S3_ACCESS_KEY
        $script:S3SecretKey = $env:S3_SECRET_KEY

        # S3 URL format for SQL Server: s3://endpoint/bucket/path
        # MinIO uses path-style URLs
        $script:S3BaseUrl = "s3://$($script:S3Endpoint)/$($script:S3Bucket)"

        # Credential name for SQL Server
        $script:S3CredentialName = "S3BackupCredential"

        # Load dbatools
        if (-not (Get-Module dbatools)) {
            Import-Module dbatools.library
            try {
                Import-Module dbatools -ErrorAction Stop
            } catch {
                Write-Warning "Importing dbatools from source"
                Import-Module ./dbatools.psd1 -Force
            }
        }
    }

    Context "SQL Server 2022 S3 backup prerequisites" {
        It "Should be connected to SQL Server 2022 or later" {
            $server = Connect-DbaInstance -SqlInstance localhost -SqlCredential $cred
            $server.VersionMajor | Should -BeGreaterOrEqual 16
            Write-Host "Connected to SQL Server version: $($server.Version)"
        }

        It "Should create an S3 credential on the SQL Server" {
            # S3 credential format: IDENTITY = 'S3 Access Key', SECRET = 'AccessKeyID:SecretKeyID'
            $secretString = "$($script:S3AccessKey):$($script:S3SecretKey)"
            $securePassword = ConvertTo-SecureString -String $secretString -AsPlainText -Force

            $splatCredential = @{
                SqlInstance    = "localhost"
                SqlCredential  = $cred
                Name           = $script:S3CredentialName
                Identity       = "S3 Access Key"
                SecurePassword = $securePassword
                Force          = $true
            }
            $newCred = New-DbaCredential @splatCredential

            # Verify credential was created
            $newCred | Should -Not -BeNullOrEmpty
            $newCred.Name | Should -Be $script:S3CredentialName
            $newCred.Identity | Should -Be "S3 Access Key"
        }
    }

    Context "Backup-DbaDatabase to S3" {
        BeforeAll {
            $script:TestDbName = "dbatoolsci_s3backup"

            # Create test database
            $null = New-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Name $script:TestDbName -RecoveryModel Full

            # Insert some test data
            $server = Connect-DbaInstance -SqlInstance localhost -SqlCredential $cred
            $server.Query("CREATE TABLE TestTable (ID INT, Name VARCHAR(100))", $script:TestDbName)
            $server.Query("INSERT INTO TestTable VALUES (1, 'Test Row 1'), (2, 'Test Row 2')", $script:TestDbName)
        }

        AfterAll {
            # Cleanup test database
            $null = Remove-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Database $script:TestDbName -Confirm:$false
        }

        It "Should backup database to S3 using StorageBaseUrl parameter" {
            $backupFile = "$($script:TestDbName)_full.bak"

            $splatBackup = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Database          = $script:TestDbName
                StorageBaseUrl    = $script:S3BaseUrl
                StorageCredential = $script:S3CredentialName
                FilePath          = $backupFile
                Type              = "Full"
            }
            $result = Backup-DbaDatabase @splatBackup

            $result | Should -Not -BeNullOrEmpty
            $result.BackupComplete | Should -BeTrue
            $result.DeviceType | Should -Be "URL"
            $result.BackupPath | Should -BeLike "s3://*"
        }

        It "Should backup database to S3 using AzureBaseUrl alias for backward compatibility" {
            $backupFile = "$($script:TestDbName)_full_alias.bak"

            $splatBackup = @{
                SqlInstance     = "localhost"
                SqlCredential   = $cred
                Database        = $script:TestDbName
                AzureBaseUrl    = $script:S3BaseUrl
                AzureCredential = $script:S3CredentialName
                FilePath        = $backupFile
                Type            = "Full"
            }
            $result = Backup-DbaDatabase @splatBackup

            $result | Should -Not -BeNullOrEmpty
            $result.BackupComplete | Should -BeTrue
            $result.DeviceType | Should -Be "URL"
        }

        It "Should backup a transaction log to S3" {
            $backupFile = "$($script:TestDbName)_log.trn"

            $splatBackup = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Database          = $script:TestDbName
                StorageBaseUrl    = $script:S3BaseUrl
                StorageCredential = $script:S3CredentialName
                FilePath          = $backupFile
                Type              = "Log"
            }
            $result = Backup-DbaDatabase @splatBackup

            $result | Should -Not -BeNullOrEmpty
            $result.BackupComplete | Should -BeTrue
            $result.Type | Should -Be "Log"
        }

        It "Should backup a differential to S3" {
            $backupFile = "$($script:TestDbName)_diff.bak"

            $splatBackup = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Database          = $script:TestDbName
                StorageBaseUrl    = $script:S3BaseUrl
                StorageCredential = $script:S3CredentialName
                FilePath          = $backupFile
                Type              = "Differential"
            }
            $result = Backup-DbaDatabase @splatBackup

            $result | Should -Not -BeNullOrEmpty
            $result.BackupComplete | Should -BeTrue
            $result.Type | Should -Be "Differential"
        }

        It "Should backup with custom MaxTransferSize for S3" {
            $backupFile = "$($script:TestDbName)_maxtransfer.bak"

            $splatBackup = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Database          = $script:TestDbName
                StorageBaseUrl    = $script:S3BaseUrl
                StorageCredential = $script:S3CredentialName
                FilePath          = $backupFile
                Type              = "Full"
                MaxTransferSize   = 10485760
                CompressBackup    = $true
            }
            $result = Backup-DbaDatabase @splatBackup

            $result | Should -Not -BeNullOrEmpty
            $result.BackupComplete | Should -BeTrue
        }
    }

    Context "Get-DbaBackupInformation from S3" {
        BeforeAll {
            $script:TestDbName2 = "dbatoolsci_s3info"

            # Create and backup test database
            $null = New-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Name $script:TestDbName2 -RecoveryModel Full

            $script:S3BackupFile = "$($script:TestDbName2)_info.bak"
            $splatBackup = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Database          = $script:TestDbName2
                StorageBaseUrl    = $script:S3BaseUrl
                StorageCredential = $script:S3CredentialName
                FilePath          = $script:S3BackupFile
                Type              = "Full"
            }
            $null = Backup-DbaDatabase @splatBackup
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Database $script:TestDbName2 -Confirm:$false
        }

        It "Should read backup information from S3 URL" {
            $s3Path = "$($script:S3BaseUrl)/$($script:S3BackupFile)"

            $splatInfo = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Path              = $s3Path
                StorageCredential = $script:S3CredentialName
            }
            $result = Get-DbaBackupInformation @splatInfo

            $result | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $script:TestDbName2
            $result.Type | Should -Be "Database"
        }
    }

    Context "Restore-DbaDatabase from S3" {
        BeforeAll {
            $script:TestDbName3 = "dbatoolsci_s3restore"
            $script:RestoreDbName = "dbatoolsci_s3restored"

            # Create and backup test database
            $null = New-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Name $script:TestDbName3 -RecoveryModel Full

            # Add test data
            $server = Connect-DbaInstance -SqlInstance localhost -SqlCredential $cred
            $server.Query("CREATE TABLE RestoreTest (ID INT, Value VARCHAR(50))", $script:TestDbName3)
            $server.Query("INSERT INTO RestoreTest VALUES (100, 'S3 Restore Test')", $script:TestDbName3)

            # Backup to S3
            $script:S3RestoreBackupFile = "$($script:TestDbName3)_restore.bak"
            $splatBackup = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Database          = $script:TestDbName3
                StorageBaseUrl    = $script:S3BaseUrl
                StorageCredential = $script:S3CredentialName
                FilePath          = $script:S3RestoreBackupFile
                Type              = "Full"
            }
            $null = Backup-DbaDatabase @splatBackup
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Database $script:TestDbName3 -Confirm:$false
            $null = Remove-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Database $script:RestoreDbName -Confirm:$false
        }

        It "Should restore database from S3 backup" {
            $s3Path = "$($script:S3BaseUrl)/$($script:S3RestoreBackupFile)"

            $splatRestore = @{
                SqlInstance         = "localhost"
                SqlCredential       = $cred
                Path                = $s3Path
                DatabaseName        = $script:RestoreDbName
                StorageCredential   = $script:S3CredentialName
                ReplaceDbNameInFile = $true
            }
            $result = Restore-DbaDatabase @splatRestore

            $result | Should -Not -BeNullOrEmpty
            $result.RestoreComplete | Should -BeTrue
            $result.Database | Should -Be $script:RestoreDbName

            # Verify data was restored
            $server = Connect-DbaInstance -SqlInstance localhost -SqlCredential $cred
            $data = $server.Query("SELECT * FROM RestoreTest", $script:RestoreDbName)
            $data.ID | Should -Be 100
            $data.Value | Should -Be "S3 Restore Test"
        }

        It "Should restore using AzureCredential alias for backward compatibility" {
            $s3Path = "$($script:S3BaseUrl)/$($script:S3RestoreBackupFile)"
            $restoreDbAlias = "$($script:RestoreDbName)_alias"

            # Remove if exists from previous test
            $null = Remove-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Database $restoreDbAlias -Confirm:$false -ErrorAction SilentlyContinue

            $splatRestore = @{
                SqlInstance         = "localhost"
                SqlCredential       = $cred
                Path                = $s3Path
                DatabaseName        = $restoreDbAlias
                AzureCredential     = $script:S3CredentialName
                ReplaceDbNameInFile = $true
            }
            $result = Restore-DbaDatabase @splatRestore

            $result | Should -Not -BeNullOrEmpty
            $result.RestoreComplete | Should -BeTrue

            # Cleanup
            $null = Remove-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Database $restoreDbAlias -Confirm:$false
        }
    }

    Context "S3 directory enumeration limitations" {
        BeforeAll {
            # This context validates that SQL Server cannot enumerate S3 bucket contents using T-SQL
            # (xp_dirtree/sys.dm_os_enumerate_filesystem don't support S3 protocol)
            # Get-DbaBackupInformation should detect S3 URLs and handle them appropriately

            $script:TestDbName5 = "dbatoolsci_s3enum"

            # Create and backup a database to S3 for enumeration testing
            $null = New-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Name $script:TestDbName5 -RecoveryModel Full

            # Create multiple backup files in S3 to test enumeration behavior
            $script:S3EnumFolder = "enumtest"
            $splatBackup1 = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Database          = $script:TestDbName5
                StorageBaseUrl    = "$($script:S3BaseUrl)/$($script:S3EnumFolder)"
                StorageCredential = $script:S3CredentialName
                FilePath          = "$($script:TestDbName5)_full1.bak"
                Type              = "Full"
            }
            $null = Backup-DbaDatabase @splatBackup1

            $splatBackup2 = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Database          = $script:TestDbName5
                StorageBaseUrl    = "$($script:S3BaseUrl)/$($script:S3EnumFolder)"
                StorageCredential = $script:S3CredentialName
                FilePath          = "$($script:TestDbName5)_log1.trn"
                Type              = "Log"
            }
            $null = Backup-DbaDatabase @splatBackup2
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Database $script:TestDbName5 -Confirm:$false
        }

        It "Should handle S3 folder paths when NoXpDirTree is not specified" {
            # Get-DbaBackupInformation internally uses xp_dirtree/sys.dm_os_enumerate_filesystem
            # When given an S3 folder path, it should detect S3 and skip enumeration
            $s3FolderPath = "$($script:S3BaseUrl)/$($script:S3EnumFolder)/"

            $splatBackupInfo = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Path              = $s3FolderPath
                StorageCredential = $script:S3CredentialName
                WarningAction     = "SilentlyContinue"
            }
            $result = Get-DbaBackupInformation @splatBackupInfo

            # Should return empty because S3 enumeration is not supported via T-SQL
            $result | Should -BeNullOrEmpty
        }

        It "Should write warning message when S3 folder enumeration is attempted" {
            $s3FolderPath = "$($script:S3BaseUrl)/$($script:S3EnumFolder)/"

            # Capture warning messages
            $warningMessages = @()
            $splatBackupInfo = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Path              = $s3FolderPath
                StorageCredential = $script:S3CredentialName
                WarningVariable   = "warningMessages"
                WarningAction     = "SilentlyContinue"
            }
            $null = Get-DbaBackupInformation @splatBackupInfo

            # Should have written a warning about S3 enumeration not being supported
            $warningMessages | Should -Not -BeNullOrEmpty
            $warningMessages -join " " | Should -BeLike "*S3 paths cannot be enumerated using T-SQL*"
        }

        It "Should work with explicit S3 file paths (not folders)" {
            # While folder enumeration doesn't work, explicit file paths should work
            $s3FilePath = "$($script:S3BaseUrl)/$($script:S3EnumFolder)/$($script:TestDbName5)_full1.bak"

            $splatBackupInfo = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Path              = $s3FilePath
                StorageCredential = $script:S3CredentialName
            }
            $result = Get-DbaBackupInformation @splatBackupInfo

            # Should successfully read the specific file
            $result | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $script:TestDbName5
            $result.Type | Should -Be "Database"
        }

        It "Should successfully enumerate local file system paths (contrast with S3)" {
            # Create a local backup to verify enumeration works for non-S3 paths
            # Use cross-platform temp path (Linux uses /tmp, Windows uses C:\temp or similar)
            $tempRoot = [System.IO.Path]::GetTempPath()
            $localBackupPath = Join-Path -Path $tempRoot -ChildPath "dbatools_s3test"
            $null = New-Item -Path $localBackupPath -ItemType Directory -Force -ErrorAction SilentlyContinue

            $localBackupFile = Join-Path -Path $localBackupPath -ChildPath "local_test.bak"
            $splatLocalBackup = @{
                SqlInstance   = "localhost"
                SqlCredential = $cred
                Database      = $script:TestDbName5
                FilePath      = $localBackupFile
                Type          = "Full"
            }
            $localBackupResult = Backup-DbaDatabase @splatLocalBackup
            $localBackupResult.BackupComplete | Should -BeTrue

            # Restore using folder path - this tests that local folder enumeration works
            # (in contrast to S3 where folder enumeration is not supported)
            $null = Remove-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Database $script:TestDbName5 -Confirm:$false -ErrorAction SilentlyContinue

            $splatRestore = @{
                SqlInstance         = "localhost"
                SqlCredential       = $cred
                Path                = $localBackupPath
            }
            $result = Restore-DbaDatabase @splatRestore

            # Should successfully restore - proving local folder enumeration works
            $result | Should -Not -BeNullOrEmpty
            $result.RestoreComplete | Should -BeTrue
            $result.Database | Should -Be $script:TestDbName5

            # Cleanup
            $null = Remove-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Database $restoreDbName -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item -Path $localBackupPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Should require PowerShell-based enumeration for S3 (validation test)" {
            # This test demonstrates the correct approach: using PowerShell to enumerate S3
            # Since we're using MinIO in tests, we need to use AWS PowerShell module
            # This is a validation that the workaround approach is correct

            # Skip if AWS.Tools.S3 not available (CI environments may not have it)
            $hasAwsModule = $null -ne (Get-Module -ListAvailable -Name AWS.Tools.S3)
            if (-not $hasAwsModule) {
                Set-ItResult -Skipped -Because "AWS.Tools.S3 module not available"
                return
            }

            # This demonstrates the recommended approach from the documentation
            # Users should use Get-S3Object to list files, then pass paths to Get-DbaBackupInformation/Restore-DbaDatabase
            Import-Module AWS.Tools.S3 -ErrorAction Stop

            # For MinIO (S3-compatible), use EndpointUrl with ForcePathStyleAddressing
            # Note: $script:S3Endpoint is "minio:9000" which is a Docker network hostname
            # The AWS SDK runs on the host, so we need to use localhost:9000 instead
            $hostEndpoint = $script:S3Endpoint -replace "^minio:", "localhost:"
            $splatListObjects = @{
                BucketName               = $script:S3Bucket
                Prefix                   = "$($script:S3EnumFolder)/"
                EndpointUrl              = "https://$hostEndpoint"
                AccessKey                = $script:S3AccessKey
                SecretKey                = $script:S3SecretKey
                ForcePathStyleAddressing = $true
            }
            $s3Objects = Get-S3Object @splatListObjects

            # PowerShell CAN enumerate S3 - this is the correct approach
            $s3Objects | Should -Not -BeNullOrEmpty
            $s3Objects.Key | Should -Contain "$($script:S3EnumFolder)/$($script:TestDbName5)_full1.bak"
            $s3Objects.Key | Should -Contain "$($script:S3EnumFolder)/$($script:TestDbName5)_log1.trn"

            # Now demonstrate using those paths with Get-DbaBackupInformation
            $backupPaths = $s3Objects | ForEach-Object {
                "$($script:S3BaseUrl)/$($_.Key)"
            }

            $splatBackupInfo = @{
                SqlInstance       = "localhost"
                SqlCredential     = $cred
                Path              = $backupPaths
                StorageCredential = $script:S3CredentialName
            }
            $backupInfo = Get-DbaBackupInformation @splatBackupInfo

            # Should successfully read backup information for all files
            $backupInfo | Should -Not -BeNullOrEmpty
            $backupInfo.Count | Should -Be 2
            $backupInfo.Database | Should -Contain $script:TestDbName5
        }
    }

    #Context "Test-DbaBackupInformation with S3" {
    #    BeforeAll {
    #        $script:TestDbName4 = "dbatoolsci_s3test"
    #
    #        # Create and backup test database
    #        $null = New-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Name $script:TestDbName4 -RecoveryModel Full
    #
    #        $script:S3TestBackupFile = "$($script:TestDbName4)_test.bak"
    #        $splatBackup = @{
    #            SqlInstance       = "localhost"
    #            SqlCredential     = $cred
    #            Database          = $script:TestDbName4
    #            StorageBaseUrl    = $script:S3BaseUrl
    #            StorageCredential = $script:S3CredentialName
    #            FilePath          = $script:S3TestBackupFile
    #            Type              = "Full"
    #        }
    #        $null = Backup-DbaDatabase @splatBackup
    #    }
    #
    #    AfterAll {
    #        $null = Remove-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Database $script:TestDbName4 -Confirm:$false
    #    }
    #
    #    It "Should validate S3 backup information" {
    #        $s3Path = "$($script:S3BaseUrl)/$($script:S3TestBackupFile)"
    #
    #        $splatInfo = @{
    #            SqlInstance       = "localhost"
    #            SqlCredential     = $cred
    #            Path              = $s3Path
    #            StorageCredential = $script:S3CredentialName
    #        }
    #        $backupInfo = Get-DbaBackupInformation @splatInfo
    #
    #        $splatTest = @{
    #            BackupHistory = $backupInfo
    #            SqlInstance   = "localhost"
    #            SqlCredential = $cred
    #            VerifyOnly    = $true
    #        }
    #        $result = Test-DbaBackupInformation @splatTest
    #
    #        $result | Should -Not -BeNullOrEmpty
    #        # S3 URLs should pass validation - they are skipped for cloud paths
    #    }
    #}

    Context "Cleanup" {
        It "Should remove the S3 credential" {
            $splatRemoveCred = @{
                SqlInstance   = "localhost"
                SqlCredential = $cred
                Credential    = $script:S3CredentialName
                Confirm       = $false
            }
            $null = Remove-DbaCredential @splatRemoveCred

            $deletedCred = Get-DbaCredential -SqlInstance localhost -SqlCredential $cred -Name $script:S3CredentialName
            $deletedCred | Should -BeNullOrEmpty
        }
    }
}