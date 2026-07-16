Describe "Integration Tests" -Tag "IntegrationTests" {
    $hasAzureServicePrincipal = [bool]($env:TENANTID -and $env:CLIENTID -and $env:CLIENTSECRET)

    BeforeAll {
        $password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sqladmin", $password

        $PSDefaultParameterValues["*:SqlInstance"] = "localhost"
        $PSDefaultParameterValues["*:Source"] = "localhost"
        $PSDefaultParameterValues["*:Destination"] = "localhost:14333"
        $PSDefaultParameterValues["*:Primary"] = "localhost"
        $PSDefaultParameterValues["*:Mirror"] = "localhost:14333"
        $PSDefaultParameterValues["*:SqlCredential"] = $cred
        $PSDefaultParameterValues["*:SourceSqlCredential"] = $cred
        $PSDefaultParameterValues["*:DestinationSqlCredential"] = $cred
        $PSDefaultParameterValues["*:PrimarySqlCredential"] = $cred
        $PSDefaultParameterValues["*:MirrorSqlCredential"] = $cred
        $PSDefaultParameterValues["*:WitnessSqlCredential"] = $cred
        $PSDefaultParameterValues["*:Confirm"] = $false
        $PSDefaultParameterValues["*:SharedPath"] = "/shared"
        $global:ProgressPreference = "SilentlyContinue"

        #$null = Get-XPlatVariable | Where-Object { $PSItem -notmatch "Copy-", "Migration" } | Sort-Object
        # load dbatools-lib
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

    It "migrates" {
        $params = @{
            MasterKeyPassword = $cred.Password
            BackupRestore     = $true
            Exclude           = "DatabaseMail", "LinkedServers", "Credentials", "DataCollector", "EndPoints", "PolicyManagement", "ResourceGovernor", "BackupDevices"
        }
        # something is up with docker on actions, adjust accordingly for the cert test
        $initialcertcount = (Get-DbaDbCertificate -SqlInstance localhost:14333 -Database master).Count
        $null = New-DbaDbCertificate -Name migrateme -Database master -Confirm:$false
        $results = Start-DbaMigration @params
        $results.Name | Should -Contain "Northwind"
        $results | Where-Object Name -eq "Northwind" | Select-Object -ExpandProperty Status | Should -Be "Successful"
        $results | Where-Object Name -eq "migrateme" | Select-Object -ExpandProperty Status | Should -Be "Successful"
        (Get-DbaDbCertificate -SqlInstance localhost:14333 -Database master).Count | Should -BeGreaterThan $initialcertcount
    }

    It "publishes a package" {
        $db = New-DbaDatabase
        $dbname = $db.Name
        $null = $db.Query("CREATE TABLE dbo.example (id int, PRIMARY KEY (id));
            INSERT dbo.example
            SELECT top 100 object_id
            FROM sys.objects")

        $publishprofile = New-DbaDacProfile -Database $dbname -Path /tmp
        $extractOptions = New-DbaDacOption -Action Export
        $extractOptions.ExtractAllTableData = $true
        $dacpac = Export-DbaDacPackage -Database $dbname -DacOption $extractOptions

        $results = $dacpac | Publish-DbaDacPackage -PublishXml $publishprofile.FileName -Database $dbname -SqlInstance localhost:14333 -Confirm:$false
        $results.Result | Should -BeLike '*Update complete.*'
        $ids = Invoke-DbaQuery -Database $dbname -SqlInstance localhost:14333 -Query 'SELECT id FROM dbo.example'
        $ids.id | Should -Not -BeNullOrEmpty
    }

    It "sets up a mirror" {
        $newdb = New-DbaDatabase
        $params = @{
            Database = $newdb.Name
            Force    = $true
        }

        Invoke-DbaDbMirroring @params | Select-Object -ExpandProperty Status | Should -Be "Success"
        Get-DbaDbMirror | Select-Object -ExpandProperty MirroringPartner | Should -Be "TCP://mssql2:5022"
    }

    It "gets some permissions" {
        $dbName = "UserPermission"
        $sql = @'
create user alice without login;
create user bob without login;
create role userrole AUTHORIZATION dbo;
exec sp_addrolemember 'userrole','alice';
exec sp_addrolemember 'userrole','bob';
'@

        $db = New-DbaDatabase -Name $dbName
        $db.ExecuteNonQuery($sql)

        $results = Get-DbaUserPermission -Database $dbName -WarningVariable warn

        $null = Remove-DbaDatabase -Database $dbName -Confirm:$false

        $warn | Should -BeNullOrEmpty
        ($results.Object | Select-Object -Unique).Count | Should -Be 2
        foreach ($result in $results) {
            $results.Object | Should -BeIn "SERVER", $dbName
            if ($result.Object -eq $dbName -and $result.RoleSecurableClass -eq 'DATABASE') {
                $result.Securable | Should -Be $dbName
            }
        }
    }

    It "attempts to balance" {
        $results = Invoke-DbaBalanceDataFiles -Database "Northwind" -Force
        $results.Database | Should -Be "Northwind"
    }

    It "converts to an XE Session" {
        $sql = "-- Create a Queue
                declare @rc int
                declare @TraceID int
                declare @maxfilesize bigint
                set @maxfilesize = 5
                exec @rc = sp_trace_create @TraceID output, 0, N'/tmp/', @maxfilesize, NULL

                -- Set the events
                declare @on bit
                set @on = 1
                exec sp_trace_setevent @TraceID, 14, 1, @on
                exec sp_trace_setevent @TraceID, 14, 9, @on
                exec sp_trace_setevent @TraceID, 14, 10, @on
                exec sp_trace_setevent @TraceID, 14, 11, @on
                exec sp_trace_setevent @TraceID, 14, 6, @on
                exec sp_trace_setevent @TraceID, 14, 12, @on
                exec sp_trace_setevent @TraceID, 14, 14, @on
                exec sp_trace_setevent @TraceID, 15, 11, @on
                exec sp_trace_setevent @TraceID, 15, 6, @on
                exec sp_trace_setevent @TraceID, 15, 9, @on
                exec sp_trace_setevent @TraceID, 15, 10, @on
                exec sp_trace_setevent @TraceID, 15, 12, @on
                exec sp_trace_setevent @TraceID, 15, 13, @on
                exec sp_trace_setevent @TraceID, 15, 14, @on
                exec sp_trace_setevent @TraceID, 15, 15, @on
                exec sp_trace_setevent @TraceID, 15, 16, @on
                exec sp_trace_setevent @TraceID, 15, 17, @on
                exec sp_trace_setevent @TraceID, 15, 18, @on
                exec sp_trace_setevent @TraceID, 17, 1, @on
                exec sp_trace_setevent @TraceID, 17, 9, @on
                exec sp_trace_setevent @TraceID, 17, 10, @on
                exec sp_trace_setevent @TraceID, 17, 11, @on
                exec sp_trace_setevent @TraceID, 17, 6, @on
                exec sp_trace_setevent @TraceID, 17, 12, @on
                exec sp_trace_setevent @TraceID, 17, 14, @on
                exec sp_trace_setevent @TraceID, 10, 9, @on
                exec sp_trace_setevent @TraceID, 10, 2, @on
                exec sp_trace_setevent @TraceID, 10, 10, @on
                exec sp_trace_setevent @TraceID, 10, 6, @on
                exec sp_trace_setevent @TraceID, 10, 11, @on
                exec sp_trace_setevent @TraceID, 10, 12, @on
                exec sp_trace_setevent @TraceID, 10, 13, @on
                exec sp_trace_setevent @TraceID, 10, 14, @on
                exec sp_trace_setevent @TraceID, 10, 15, @on
                exec sp_trace_setevent @TraceID, 10, 16, @on
                exec sp_trace_setevent @TraceID, 10, 17, @on
                exec sp_trace_setevent @TraceID, 10, 18, @on
                exec sp_trace_setevent @TraceID, 12, 1, @on
                exec sp_trace_setevent @TraceID, 12, 9, @on
                exec sp_trace_setevent @TraceID, 12, 11, @on
                exec sp_trace_setevent @TraceID, 12, 6, @on
                exec sp_trace_setevent @TraceID, 12, 10, @on
                exec sp_trace_setevent @TraceID, 12, 12, @on
                exec sp_trace_setevent @TraceID, 12, 13, @on
                exec sp_trace_setevent @TraceID, 12, 14, @on
                exec sp_trace_setevent @TraceID, 12, 15, @on
                exec sp_trace_setevent @TraceID, 12, 16, @on
                exec sp_trace_setevent @TraceID, 12, 17, @on
                exec sp_trace_setevent @TraceID, 12, 18, @on
                exec sp_trace_setevent @TraceID, 13, 1, @on
                exec sp_trace_setevent @TraceID, 13, 9, @on
                exec sp_trace_setevent @TraceID, 13, 11, @on
                exec sp_trace_setevent @TraceID, 13, 6, @on
                exec sp_trace_setevent @TraceID, 13, 10, @on
                exec sp_trace_setevent @TraceID, 13, 12, @on
                exec sp_trace_setevent @TraceID, 13, 14, @on

                -- Set the Filters
                declare @intfilter int
                declare @bigintfilter bigint

                exec sp_trace_setfilter @TraceID, 10, 0, 7, N'SQL Server Profiler - 934a8575-0dc1-4937-bde1-edac1cb9691f'
                -- Set the trace status to start
                exec sp_trace_setstatus @TraceID, 1

                -- display trace id for future references
                select TraceID=@TraceID"
        $server = Connect-DbaInstance
        $traceid = ($server.Query($sql)).TraceID

        $null = Get-DbaTrace -Id $traceid | ConvertTo-DbaXESession -Name "dbatoolsci-session"
        $results = Start-DbaXESession -Session "dbatoolsci-session"
        $results.Name | Should -Be "dbatoolsci-session"
        $results.Status | Should -Be "Running"
        $results.Targets.Name | Should -Be "package0.event_file"
    }

    It "tests the instance name" {
        $results = Test-DbaInstanceName
        $results.ServerName | Should -Be "mssql1"
    }

    It "creates a new database user" {
        $results = New-DbaDbUser -Database msdb -Username sqladmin -IncludeSystem
        $results.Name | Should -Be sqladmin
    }

    It "returns some permission" {
        Get-DbaPermission -Database tempdb | Should -Not -Be $null
    }

    # Takes two minutes in GH, very boring
    It -Skip "returns the master key" {
        (Get-DbaDbMasterKey).Database | Should -Be "master"
    }

    It "stops an xe session" {
        (Stop-DbaXESession -Session "dbatoolsci-session").Name | Should -Be "dbatoolsci-session"
    }

    It "tests tempdb configs" {
        (Test-DbaTempDbConfig).Rule | Should -Contain "File Growth in Percent"
    }

    if ((dpkg --print-architecture) -notmatch "arm") {
        It "creates a snapshot" {
            (New-DbaDbSnapshot -Database pubs).SnapshotOf | Should -Be "pubs"
        }
    }

    It "gets an XE template on Linux" {
        (Get-DbaXESessionTemplate | Measure-Object).Count | Should -BeGreaterThan 40
    }

    It "copies a certificate" {
        $passwd = ConvertTo-SecureString "dbatools.IOXYZ" -AsPlainText -Force
        $null = New-DbaDbMasterKey -Database tempdb -SecurePassword $passwd -Confirm:$false
        $certname = "Cert_$(Get-Random)"
        $null = New-DbaDbCertificate -Name $certname -Database tempdb -Confirm:$false

        $params1 = @{
            EncryptionPassword = $passwd
            MasterKeyPassword  = $passwd
            Database           = "tempdb"
            SharedPath         = "/shared"
        }
        $results = Copy-DbaDbCertificate @params1 -Confirm:$false | Where-Object SourceDatabase -eq tempdb | Select-Object -First 1
        $results.Notes | Should -Be $null
        $results.Status | Should -Be "Successful"
    }

    It -Skip:(-not $hasAzureServicePrincipal) "connects to Azure" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"
        Connect-DbaInstance -SqlInstance "Server=dbatoolstest.database.windows.net; Authentication=Active Directory Service Principal; Database=test; User Id=$env:CLIENTID; Password=$env:CLIENTSECRET;" | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"
    }

    It -Skip:(-not $hasAzureServicePrincipal) "gets a database from Azure" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        $server = Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID
        (Get-DbaDatabase -SqlInstance $server -Database test).Name | Should -Be "test"
    }

    It -Skip:([bool]$env:DBATOOLS_GALLERY_TEST) "copies table data to Azure SQL using an access token" {
        $PSDefaultParameterValues.Clear()
        $sourceInstance = if ($env:DBATOOLS_SQL_SOURCE) { $env:DBATOOLS_SQL_SOURCE } else { "localhost" }
        $tableName = "dbatools_copy_access_token_$([guid]::NewGuid().ToString('N'))"
        $sourceServer = Connect-DbaInstance -SqlInstance $sourceInstance -SqlCredential $cred -Database tempdb

        if ($env:AZURE_SQL_ACCESS_TOKEN) {
            $destinationServer = Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -Database test -AccessToken $env:AZURE_SQL_ACCESS_TOKEN
        } elseif ($env:TENANTID -and $env:CLIENTID -and $env:CLIENTSECRET) {
            $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
            $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
            $destinationServer = Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -Database test -SqlCredential $azurecred -Tenant $env:TENANTID
        } else {
            throw "The Azure SQL access-token integration test requires AZURE_SQL_ACCESS_TOKEN or TENANTID, CLIENTID, and CLIENTSECRET."
        }

        try {
            $sourceServer.Query("CREATE TABLE dbo.[$tableName] (Id int NOT NULL, Value int NOT NULL); INSERT dbo.[$tableName] (Id, Value) VALUES (1, 10), (2, 20), (3, 30)", "tempdb")
            $destinationServer.Query("CREATE TABLE dbo.[$tableName] (Id int NOT NULL, Value int NOT NULL)", "test")

            $splatCopy = @{
                SqlInstance         = $sourceServer
                Destination         = $destinationServer
                Database            = "tempdb"
                DestinationDatabase = "test"
                Table               = "dbo.$tableName"
                DestinationTable    = "dbo.$tableName"
                EnableException     = $true
            }
            $result = Copy-DbaDbTableData @splatCopy
            $destinationRows = $destinationServer.Query("SELECT COUNT(*) AS CopiedRowCount, SUM(Value) AS TotalValue FROM dbo.[$tableName]", "test")

            $result.RowsCopied | Should -Be 3
            $destinationRows.CopiedRowCount | Should -Be 3
            $destinationRows.TotalValue | Should -Be 60
        } finally {
            $sourceServer.ConnectionContext.SqlConnectionObject.Close()
            $sourceServer.Query("DROP TABLE IF EXISTS dbo.[$tableName]", "tempdb")
            $destinationServer.Query("DROP TABLE IF EXISTS dbo.[$tableName]", "test")
        }
    }

    It -Skip:(-not $env:azurepasswd) "sets up log shipping to Azure blob storage using SAS token" {
        # Restore credentials after Azure tests cleared PSDefaultParameterValues
        $password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sqladmin", $password

        $azureUrl = "https://dbatools.blob.core.windows.net/dbatools"
        $dbName = "dbatoolsci_logship_azure"

        # Create SAS token credential on both instances
        $primaryServer = Connect-DbaInstance -SqlInstance localhost -SqlCredential $cred
        if (Get-DbaCredential -SqlInstance localhost -SqlCredential $cred -Name "[$azureUrl]") {
            $primaryServer.Query("DROP CREDENTIAL [$azureUrl]")
        }
        # Strip leading ? from SAS token if present
        $sasToken = $env:azurepasswd.TrimStart("?")
        $sql = "CREATE CREDENTIAL [$azureUrl] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$sasToken'"
        $primaryServer.Query($sql)

        $secondaryServer = Connect-DbaInstance -SqlInstance localhost:14333 -SqlCredential $cred
        if (Get-DbaCredential -SqlInstance localhost:14333 -SqlCredential $cred -Name "[$azureUrl]") {
            $secondaryServer.Query("DROP CREDENTIAL [$azureUrl]")
        }
        $secondaryServer.Query($sql)

        # Create test database
        $null = New-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Name $dbName

        # Set up log shipping
        $splatLogShipping = @{
            SourceSqlInstance        = "localhost"
            SourceSqlCredential      = $cred
            DestinationSqlInstance   = "localhost:14333"
            DestinationSqlCredential = $cred
            Database                 = $dbName
            AzureBaseUrl             = $azureUrl
            GenerateFullBackup       = $true
            Force                    = $true
        }
        $maximumRetries = 10
        $isTransientAzureBlobFailure = $false
        foreach ($attempt in 0..$maximumRetries) {
            $Error.Clear()
            $results = Invoke-DbaDbLogShipping @splatLogShipping
            if ($results.Result -eq "Success") {
                break
            }

            $errorText = $Error | Out-String
            $isTransientAzureBlobFailure = $errorText -match "Cannot open backup device 'https://.*blob\.core\.windows\.net.*Operating system error 50"
            if (-not $isTransientAzureBlobFailure -or $attempt -eq $maximumRetries) {
                break
            }

            $retryNumber = $attempt + 1
            Write-Warning "Azure Blob backup device returned transient operating system error 50; retry $retryNumber of $maximumRetries in 10 seconds."
            Start-Sleep -Seconds 10
        }

        # If failed, output detailed error information for debugging
        if ($results.Result -ne "Success") {
            Write-Host "=== Log Shipping Failed ==="
            Write-Host "Results object:"
            $results | Format-List * | Out-String | Write-Host
            Write-Host "`nError details:"
            $Error | Select-Object -First 5 | ForEach-Object {
                Write-Host "---"
                Write-Host "Exception: $($_.Exception.Message)"
                Write-Host "Category: $($_.CategoryInfo.Category)"
                Write-Host "TargetObject: $($_.TargetObject)"
                if ($_.Exception.InnerException) {
                    Write-Host "InnerException: $($_.Exception.InnerException.Message)"
                }
            }
            Write-Host "==========================="

            if ($isTransientAzureBlobFailure) {
                Set-ItResult -Skipped -Because "Azure Blob backup device still returned transient operating system error 50 after $maximumRetries retries"
                return
            }
        }

        $results.Result | Should -Be "Success"

        # Verify backup job created
        $jobs = Get-DbaAgentJob -SqlInstance localhost -SqlCredential $cred
        $backupJob = $jobs | Where-Object Name -like "*LSBackup*$dbName*"
        $backupJob | Should -Not -BeNullOrEmpty

        # Verify restore job created
        $jobs = Get-DbaAgentJob -SqlInstance localhost:14333 -SqlCredential $cred
        $restoreJob = $jobs | Where-Object Name -like "*LSRestore*$dbName*"
        $restoreJob | Should -Not -BeNullOrEmpty

        # Verify NO copy job created (Azure optimization)
        $copyJob = $jobs | Where-Object Name -like "*LSCopy*$dbName*"

        # Debug: Show all jobs if copy job exists
        if ($copyJob) {
            Write-Host "=== COPY JOB STILL EXISTS ==="
            Write-Host "All jobs on secondary:"
            $jobs | Where-Object Name -like "*$dbName*" | ForEach-Object {
                Write-Host "  - $($_.Name) (Enabled: $($_.IsEnabled))"
            }
            Write-Host "Copy job details:"
            $copyJob | Format-List Name, IsEnabled, OwnerLoginName, DateCreated | Out-String | Write-Host
            Write-Host "============================"
        }

        $copyJob | Should -BeNullOrEmpty

        # Cleanup
        $splatRemoveLogShipping = @{
            PrimarySqlInstance     = "localhost"
            PrimarySqlCredential   = $cred
            SecondarySqlInstance   = "localhost:14333"
            SecondarySqlCredential = $cred
            Database               = $dbName
            WarningAction          = "SilentlyContinue"
        }
        $null = Remove-DbaDbLogShipping @splatRemoveLogShipping
        $null = Remove-DbaDatabase -SqlInstance localhost -SqlCredential $cred -Database $dbName -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance localhost:14333 -SqlCredential $cred -Database $dbName -Confirm:$false
        $primaryServer.Query("DROP CREDENTIAL [$azureUrl]")
        $secondaryServer.Query("DROP CREDENTIAL [$azureUrl]")

        # Clean up Azure blob storage test files
        if ($env:azurepasswd) {
            try {
                $splatAzList = @(
                    "storage", "blob", "list"
                    "--account-name", "dbatools"
                    "--container-name", "dbatools"
                    "--prefix", $dbName
                    "--sas-token", $sasToken
                    "--query", "[].name"
                    "--output", "tsv"
                )
                $blobs = & az @splatAzList 2>$null
                if ($blobs) {
                    $blobs -split "`n" | Where-Object { $_ } | ForEach-Object {
                        $splatAzDelete = @(
                            "storage", "blob", "delete"
                            "--account-name", "dbatools"
                            "--container-name", "dbatools"
                            "--name", $_
                            "--sas-token", $sasToken
                            "--output", "none"
                        )
                        $null = & az @splatAzDelete 2>$null
                    }
                }
            } catch {
                # Ignore Azure cleanup errors - test may run in environments without Azure CLI
            }
        }
    }

    It -Skip:(-not $env:azurepasswd) "adds a second live secondary without replacing the Azure primary configuration" {
        $PSDefaultParameterValues.Clear()
        $azureUrl = "https://dbatools.blob.core.windows.net/dbatools"
        $dbName = "dbatoolsci_logship_addsecondary"
        $secondDbName = "${dbName}_second"
        $missingPrimaryDbName = "${dbName}_missing"
        $sasToken = $env:azurepasswd.TrimStart("?")
        $escapedSasToken = $sasToken.Replace("'", "''")
        $escapedDbName = $dbName.Replace("'", "''")
        $escapedSecondDbName = $secondDbName.Replace("'", "''")
        $primaryServer = $null
        $firstSecondaryServer = $null
        $secondSecondaryServer = $null
        $associationQuery = @"
SELECT
    ps.secondary_server AS SecondaryServer,
    ps.secondary_database AS SecondaryDatabase
FROM msdb.dbo.log_shipping_primary_databases AS pd
INNER JOIN msdb.dbo.log_shipping_primary_secondaries AS ps ON pd.primary_id = ps.primary_id
WHERE pd.primary_database = N'$escapedDbName';
"@

        function Invoke-AzureLogShippingWithRetry {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [hashtable]$Parameters
            )

            $maximumRetries = 10
            foreach ($attempt in 0..$maximumRetries) {
                $Error.Clear()
                $result = Invoke-DbaDbLogShipping @Parameters
                if ($result.Result -eq "Success") {
                    return [PSCustomObject]@{
                        CommandResult              = $result
                        PersistentTransientFailure = $false
                    }
                }

                $errorText = $Error | Out-String
                $isTransientAzureBlobFailure = $errorText -match "Cannot open backup device 'https://.*blob\.core\.windows\.net.*Operating system error 50"
                if (-not $isTransientAzureBlobFailure -or $attempt -eq $maximumRetries) {
                    return [PSCustomObject]@{
                        CommandResult              = $result
                        PersistentTransientFailure = $isTransientAzureBlobFailure
                    }
                }

                $retryNumber = $attempt + 1
                Write-Warning "Azure Blob backup device returned transient operating system error 50; retry $retryNumber of $maximumRetries in 10 seconds."
                Start-Sleep -Seconds 10
            }
        }

        try {
            $primaryServer = Connect-DbaInstance -SqlInstance localhost -SqlCredential $cred
            $firstSecondaryServer = Connect-DbaInstance -SqlInstance localhost:14333 -SqlCredential $cred
            foreach ($connectionAttempt in 1..12) {
                try {
                    $secondSecondaryServer = Connect-DbaInstance -SqlInstance localhost:14334 -SqlCredential $cred -ErrorAction Stop
                    break
                } catch {
                    if ($connectionAttempt -eq 12) {
                        throw
                    }
                    Start-Sleep -Seconds 5
                }
            }

            $createCredentialSql = "CREATE CREDENTIAL [$azureUrl] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$escapedSasToken'"
            foreach ($server in @($primaryServer, $firstSecondaryServer, $secondSecondaryServer)) {
                $server.Query("IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'$azureUrl') DROP CREDENTIAL [$azureUrl]")
                $server.Query($createCredentialSql)
            }

            $null = New-DbaDatabase -SqlInstance $primaryServer -Name $dbName

            $splatInitialLogShipping = @{
                SourceSqlInstance        = $primaryServer
                DestinationSqlInstance   = $firstSecondaryServer
                Database                 = $dbName
                AzureBaseUrl             = $azureUrl
                GenerateFullBackup       = $true
                Force                    = $true
            }
            $initialAttempt = Invoke-AzureLogShippingWithRetry -Parameters $splatInitialLogShipping
            if ($initialAttempt.PersistentTransientFailure) {
                throw "Azure Blob backup device still returned transient operating system error 50 after 10 retries"
            }
            $initialResult = $initialAttempt.CommandResult
            $initialResult.Result | Should -Be "Success"

            $primaryMetadataQuery = @"
SELECT
    pd.backup_directory AS BackupDirectory,
    pd.backup_share AS BackupShare,
    CONVERT(varchar(36), pd.backup_job_id) AS BackupJobId,
    sj.name AS BackupJob,
    sj.enabled AS BackupJobEnabled,
    COUNT(sjs.schedule_id) AS BackupScheduleCount
FROM msdb.dbo.log_shipping_primary_databases AS pd
INNER JOIN msdb.dbo.sysjobs AS sj ON pd.backup_job_id = sj.job_id
LEFT JOIN msdb.dbo.sysjobschedules AS sjs ON sj.job_id = sjs.job_id
WHERE pd.primary_database = N'$escapedDbName'
GROUP BY pd.backup_directory, pd.backup_share, pd.backup_job_id, sj.name, sj.enabled;
"@
            $secondaryMetadataQuery = @"
SELECT
    sd.secondary_database AS SecondaryDatabase,
    CONVERT(varchar(36), ls.restore_job_id) AS RestoreJobId,
    sj.name AS RestoreJob,
    sj.enabled AS RestoreJobEnabled,
    COUNT(sjs.schedule_id) AS RestoreScheduleCount
FROM msdb.dbo.log_shipping_secondary_databases AS sd
INNER JOIN msdb.dbo.log_shipping_secondary AS ls ON sd.secondary_id = ls.secondary_id
INNER JOIN msdb.dbo.sysjobs AS sj ON ls.restore_job_id = sj.job_id
LEFT JOIN msdb.dbo.sysjobschedules AS sjs ON sj.job_id = sjs.job_id
WHERE sd.secondary_database = N'$escapedDbName'
GROUP BY sd.secondary_database, ls.restore_job_id, sj.name, sj.enabled;
"@
            $primaryBefore = Invoke-DbaQuery -SqlInstance $primaryServer -Database msdb -Query $primaryMetadataQuery -EnableException
            $firstSecondaryBefore = Invoke-DbaQuery -SqlInstance $firstSecondaryServer -Database msdb -Query $secondaryMetadataQuery -EnableException
            $primaryBefore | Should -Not -BeNullOrEmpty
            $firstSecondaryBefore | Should -Not -BeNullOrEmpty

            $splatAddSecondary = @{
                SourceSqlInstance        = $primaryServer
                DestinationSqlInstance   = $secondSecondaryServer
                Database                 = $dbName
                AddSecondary             = $true
                GenerateFullBackup       = $true
                SecondaryDatabaseSuffix = "_second"
                Force                    = $true
            }
            $addSecondaryAttempt = Invoke-AzureLogShippingWithRetry -Parameters $splatAddSecondary
            if ($addSecondaryAttempt.PersistentTransientFailure) {
                throw "Azure Blob backup device still returned transient operating system error 50 after 10 retries"
            }
            $addSecondaryResult = $addSecondaryAttempt.CommandResult
            $addSecondaryResult.Result | Should -Be "Success"
            $addSecondaryResult.SecondaryDatabase | Should -Be $secondDbName

            $primaryAfter = Invoke-DbaQuery -SqlInstance $primaryServer -Database msdb -Query $primaryMetadataQuery -EnableException
            $primaryAfter.BackupDirectory | Should -Be $primaryBefore.BackupDirectory
            $primaryAfter.BackupShare | Should -Be $primaryBefore.BackupShare
            $primaryAfter.BackupJobId | Should -Be $primaryBefore.BackupJobId
            $primaryAfter.BackupJob | Should -Be $primaryBefore.BackupJob
            $primaryAfter.BackupJobEnabled | Should -Be $primaryBefore.BackupJobEnabled
            $primaryAfter.BackupScheduleCount | Should -Be $primaryBefore.BackupScheduleCount

            $associations = @(Invoke-DbaQuery -SqlInstance $primaryServer -Database msdb -Query $associationQuery -EnableException)
            $associations.Count | Should -Be 2
            $associations.SecondaryDatabase | Should -Contain $dbName
            $associations.SecondaryDatabase | Should -Contain $secondDbName
            @($associations.SecondaryServer | Select-Object -Unique).Count | Should -Be 2

            $firstSecondaryAfter = Invoke-DbaQuery -SqlInstance $firstSecondaryServer -Database msdb -Query $secondaryMetadataQuery -EnableException
            $firstSecondaryAfter.RestoreJobId | Should -Be $firstSecondaryBefore.RestoreJobId
            $firstSecondaryAfter.RestoreJob | Should -Be $firstSecondaryBefore.RestoreJob
            $firstSecondaryAfter.RestoreJobEnabled | Should -Be $firstSecondaryBefore.RestoreJobEnabled
            $firstSecondaryAfter.RestoreScheduleCount | Should -Be $firstSecondaryBefore.RestoreScheduleCount

            $secondSecondaryMetadataQuery = $secondaryMetadataQuery.Replace("N'$escapedDbName'", "N'$escapedSecondDbName'")
            $secondSecondaryMetadata = Invoke-DbaQuery -SqlInstance $secondSecondaryServer -Database msdb -Query $secondSecondaryMetadataQuery -EnableException
            $secondSecondaryMetadata.SecondaryDatabase | Should -Be $secondDbName
            $secondSecondaryMetadata.RestoreJob | Should -BeLike "*LSRestore*$dbName*"

            $firstDatabaseState = Invoke-DbaQuery -SqlInstance $firstSecondaryServer -Database master -Query "SELECT state_desc AS State FROM sys.databases WHERE name = N'$escapedDbName'" -EnableException
            $secondDatabaseState = Invoke-DbaQuery -SqlInstance $secondSecondaryServer -Database master -Query "SELECT state_desc AS State FROM sys.databases WHERE name = N'$escapedSecondDbName'" -EnableException
            $firstDatabaseState.State | Should -Be "RESTORING"
            $secondDatabaseState.State | Should -Be "RESTORING"

            $splatAddSecondary.EnableException = $true
            { Invoke-DbaDbLogShipping @splatAddSecondary } | Should -Throw "*already associated*"
            $associationsAfterDuplicate = @(Invoke-DbaQuery -SqlInstance $primaryServer -Database msdb -Query $associationQuery -EnableException)
            $associationsAfterDuplicate.Count | Should -Be 2

            $null = New-DbaDatabase -SqlInstance $primaryServer -Name $missingPrimaryDbName
            $splatMissingPrimary = @{
                SourceSqlInstance        = $primaryServer
                DestinationSqlInstance   = $secondSecondaryServer
                Database                 = $missingPrimaryDbName
                AddSecondary             = $true
                GenerateFullBackup       = $true
                SecondaryDatabaseSuffix = "_second"
                Force                    = $true
                EnableException          = $true
            }
            { Invoke-DbaDbLogShipping @splatMissingPrimary } | Should -Throw "*not configured as a log shipping primary*"
        } finally {
            if ($primaryServer) {
                try {
                    $cleanupAssociations = @(Invoke-DbaQuery -SqlInstance $primaryServer -Database msdb -Query $associationQuery -EnableException)
                    foreach ($association in $cleanupAssociations) {
                        $escapedSecondaryServer = "$($association.SecondaryServer)".Replace("'", "''")
                        $escapedSecondaryDatabase = "$($association.SecondaryDatabase)".Replace("'", "''")
                        $primaryServer.Databases["master"].Query("EXEC dbo.sp_delete_log_shipping_primary_secondary @primary_database = N'$escapedDbName', @secondary_server = N'$escapedSecondaryServer', @secondary_database = N'$escapedSecondaryDatabase'")
                    }
                    $primaryServer.Databases["master"].Query("IF EXISTS (SELECT 1 FROM msdb.dbo.log_shipping_primary_databases WHERE primary_database = N'$escapedDbName') EXEC dbo.sp_delete_log_shipping_primary_database @database = N'$escapedDbName'")
                } catch {
                    Write-Warning "Unable to remove primary log-shipping metadata for ${dbName}: $($_.Exception.Message)"
                }
            }

            foreach ($secondary in @(
                    [PSCustomObject]@{ Server = $firstSecondaryServer; Database = $dbName; EscapedDatabase = $escapedDbName }
                    [PSCustomObject]@{ Server = $secondSecondaryServer; Database = $secondDbName; EscapedDatabase = $escapedSecondDbName }
                )) {
                if (-not $secondary.Server) {
                    continue
                }

                try {
                    $secondary.Server.Databases["master"].Query("IF EXISTS (SELECT 1 FROM msdb.dbo.log_shipping_secondary_databases WHERE secondary_database = N'$($secondary.EscapedDatabase)') EXEC dbo.sp_delete_log_shipping_secondary_database @secondary_database = N'$($secondary.EscapedDatabase)'")
                } catch {
                    Write-Warning "Unable to remove secondary log-shipping metadata for $($secondary.Database): $($_.Exception.Message)"
                }

                try {
                    $null = Remove-DbaDatabase -SqlInstance $secondary.Server -Database $secondary.Database -Confirm:$false -EnableException
                } catch {
                    Write-Warning "Unable to remove secondary database $($secondary.Database): $($_.Exception.Message)"
                }
            }

            if ($primaryServer) {
                foreach ($database in @($dbName, $missingPrimaryDbName)) {
                    try {
                        $null = Remove-DbaDatabase -SqlInstance $primaryServer -Database $database -Confirm:$false -EnableException
                    } catch {
                        Write-Warning "Unable to remove primary database ${database}: $($_.Exception.Message)"
                    }
                }
            }

            foreach ($server in @($primaryServer, $firstSecondaryServer, $secondSecondaryServer)) {
                if (-not $server) {
                    continue
                }

                try {
                    $server.Query("IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'$azureUrl') DROP CREDENTIAL [$azureUrl]")
                } catch {
                    Write-Warning "Unable to remove the Azure credential from ${server}: $($_.Exception.Message)"
                }
            }

            try {
                $splatAzList = @(
                    "storage", "blob", "list"
                    "--account-name", "dbatools"
                    "--container-name", "dbatools"
                    "--prefix", $dbName
                    "--sas-token", $sasToken
                    "--query", "[].name"
                    "--output", "tsv"
                )
                $blobs = & az @splatAzList 2>$null
                if ($blobs) {
                    $blobs -split "`n" | Where-Object { $PSItem } | ForEach-Object {
                        $splatAzDelete = @(
                            "storage", "blob", "delete"
                            "--account-name", "dbatools"
                            "--container-name", "dbatools"
                            "--name", $PSItem
                            "--sas-token", $sasToken
                            "--output", "none"
                        )
                        $null = & az @splatAzDelete 2>$null
                    }
                }
            } catch {
                Write-Warning "Unable to remove Azure test blobs for ${dbName}: $($_.Exception.Message)"
            }
        }
    }

    # Storage account key test removed - deprecated authentication method
    # - Storage account keys create page blobs (limited to 1 TB, more expensive)
    # - Microsoft recommends SAS tokens for SQL Server 2016+ (creates block blobs, up to 12.8 TB striped)
    # - Use the SAS token test above for modern Azure blob storage log shipping

    It -Skip:(-not $hasAzureServicePrincipal) "tests Get-DbaLastGoodCheckDb against Azure" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        $server = Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID
        { Get-DbaLastGoodCheckDb -SqlInstance $server } | Should -Not -Throw
    }
}


<#
Need to add tests for CSV
# fails on newer version of SMO
'Invoke-DbaWhoisActive',
'Remove-DbaAvailabilityGroup',
'Set-DbaAgReplica',
'Read-DbaAuditFile',
'Sync-DbaLoginPermission',
'Read-DbaXEFile',
'Stop-DbaXESession',
'Test-DbaTempDbConfig',
'Watch-DbaDbLogin',
'Remove-DbaDatabaseSafely',
'Test-DbaManagementObject',
'Export-DbaDacPackage'
#>
