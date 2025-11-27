Describe "Integration Tests" -Tag "IntegrationTests" {
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
            Exclude           = "LinkedServers", "Credentials", "DataCollector", "EndPoints", "PolicyManagement", "ResourceGovernor", "BackupDevices"
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

    It "installs darling data" {
        $results = Install-DbaDarlingData
        $results.Database | Select-Object -First 1 | Should -Be "master"
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

    It "connects to Azure" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"
        Connect-DbaInstance -SqlInstance "Server=dbatoolstest.database.windows.net; Authentication=Active Directory Service Principal; Database=test; User Id=$env:CLIENTID; Password=$env:CLIENTSECRET;" | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"
    }

    It "gets a database from Azure" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        $server = Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID
        (Get-DbaDatabase -SqlInstance $server -Database test).Name | Should -Be "test"
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
        $Error.Clear()
        $results = Invoke-DbaDbLogShipping @splatLogShipping

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

    # Storage account key test removed - deprecated authentication method
    # - Storage account keys create page blobs (limited to 1 TB, more expensive)
    # - Microsoft recommends SAS tokens for SQL Server 2016+ (creates block blobs, up to 12.8 TB striped)
    # - Use the SAS token test above for modern Azure blob storage log shipping

    It "tests Get-DbaLastGoodCheckDb against Azure" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        $server = Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID
        { Get-DbaLastGoodCheckDb -SqlInstance $server } | Should -Not -Throw
    }

    It "sets up an availability group and tests ReadOnlyRoutingList" {
        # Reset PSDefaultParameterValues for AG setup
        $PSDefaultParameterValues.Clear()
        $password = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sqladmin", $password

        $agName = "dbatoolsci_agrouting_$(Get-Random)"
        $certName = "dbatoolsci_AGCert_$(Get-Random)"

        try {
            # Create certificate for AG
            $null = New-DbaDbCertificate -SqlInstance localhost -SqlCredential $cred -Name $certName -Database master -Confirm:$false

            # Create AG with single replica
            $splatAg = @{
                Primary      = "localhost"
                Name         = $agName
                ClusterType  = "None"
                FailoverMode = "Manual"
                Certificate  = $certName
                SqlCredential = $cred
                Confirm      = $false
            }
            $ag = New-DbaAvailabilityGroup @splatAg
            $replicaName = $ag.PrimaryReplica

            # First, set ReadonlyRoutingConnectionUrl - required before setting ReadOnlyRoutingList
            $splatRoutingUrl = @{
                SqlInstance                  = "localhost"
                SqlCredential                = $cred
                AvailabilityGroup            = $agName
                Replica                      = $replicaName
                ReadonlyRoutingConnectionUrl = "TCP://${replicaName}:1433"
                Confirm                      = $false
            }
            $null = Set-DbaAgReplica @splatRoutingUrl

            # Test simple ordered ReadOnlyRoutingList (issue #9987)
            $splatSimpleRouting = @{
                SqlInstance         = "localhost"
                SqlCredential       = $cred
                AvailabilityGroup   = $agName
                Replica             = $replicaName
                ReadOnlyRoutingList = @($replicaName)
                Confirm             = $false
            }
            $result = Set-DbaAgReplica @splatSimpleRouting
            $result.ReadonlyRoutingList | Should -Contain $replicaName
            $result.ReadonlyRoutingList.Count | Should -Be 1

            # Test load-balanced ReadOnlyRoutingList
            $splatLoadBalanced = @{
                SqlInstance         = "localhost"
                SqlCredential       = $cred
                AvailabilityGroup   = $agName
                Replica             = $replicaName
                ReadOnlyRoutingList = @(,($replicaName))
                Confirm             = $false
            }
            $result = Set-DbaAgReplica @splatLoadBalanced
            $result.ReadonlyRoutingList | Should -Not -BeNullOrEmpty

        } finally {
            # Cleanup
            $null = Remove-DbaAvailabilityGroup -SqlInstance localhost -SqlCredential $cred -AvailabilityGroup $agName -Confirm:$false -ErrorAction SilentlyContinue
            $null = Get-DbaEndpoint -SqlInstance localhost -SqlCredential $cred -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false -ErrorAction SilentlyContinue
            $null = Remove-DbaDbCertificate -SqlInstance localhost -SqlCredential $cred -Certificate $certName -Database master -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}


<#
Need to add tests for CSV
# fails on newer version of SMO
'Invoke-DbaWhoisActive',
'Remove-DbaAvailabilityGroup',
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