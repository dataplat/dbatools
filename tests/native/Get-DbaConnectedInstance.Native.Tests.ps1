#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaConnectedInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- The pinned function declares param () with no pipeline parameter; it reads the connection cache only.
# NativeChecklist: multi-instance-failure N/A -- The command contacts no instance; it lists the connections Connect-DbaInstance already cached, several of them in every test below.
# NativeChecklist: enable-exception N/A -- The pinned function declares param () under [CmdletBinding()], so it has no -EnableException.
# NativeChecklist: switch-false N/A -- The pinned function declares no switch parameter.
# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads the connection cache.

Describe "Get-DbaConnectedInstance native" -Tag IntegrationTests {
    BeforeAll {
        $random = Get-Random
        # Every connection a test makes; AfterAll disconnects them, which also removes their cache entries.
        $nativeCreated = New-Object System.Collections.ArrayList

        function Get-NativeConnectedRow {
            param($Connection)
            foreach ($row in @(Get-DbaConnectedInstance)) {
                foreach ($entry in @($row.ConnectionObject)) {
                    if ([object]::ReferenceEquals($entry, $Connection)) {
                        $row
                        break
                    }
                }
            }
        }

        function Get-NativeMaskedConnectionString {
            param([string]$ConnectionString)
            # The absorbed private Hide-ConnectionString: the password masked with eight asterisks when present.
            $builder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $ConnectionString
            if ($builder.Password) {
                $builder.Password = "********"
            }
            $builder.ConnectionString
        }
    }

    AfterAll {
        if ($nativeCreated.Count) {
            $null = Disconnect-DbaInstance -InputObject $nativeCreated.ToArray() -Confirm:$false -WarningAction SilentlyContinue
        }
    }

    Context "Cached SMO connections" {
        It "returns a pooled SMO connection with the pinned properties, default view and masked connection string" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName "dbatoolsci-cnxpool-$random" -EnableException
            $null = $nativeCreated.Add($server)
            $key = $server.ConnectionContext.ConnectionString
            $rows = @(Get-NativeConnectedRow -Connection $server)
            $rows.Count | Should -Be 1
            $rows[0].SqlInstance | Should -Be $server.Name
            $rows[0].ConnectionType | Should -BeExactly "Microsoft.SqlServer.Management.Smo.Server"
            $rows[0].Pooled | Should -BeTrue
            $rows[0].ConnectionObject.GetType().FullName | Should -BeExactly "System.Object[]"
            $rows[0].ConnectionObject.Count | Should -Be 1
            $rows[0].ConnectionString | Should -BeExactly (Get-NativeMaskedConnectionString -ConnectionString $key)
            @($rows[0].PSObject.Properties.Name) | Should -Be @("SqlInstance", "ConnectionObject", "ConnectionType", "Pooled", "ConnectionString")
            @($rows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Be @("SqlInstance", "ConnectionType", "ConnectionObject", "Pooled")
        }

        It "returns one row, not pooled, for the non-pooled SMO connections cached under one connection string" {
            $first = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName "dbatoolsci-cnxnp-$random" -NonPooledConnection -EnableException
            $null = $nativeCreated.Add($first)
            $second = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName "dbatoolsci-cnxnp-$random" -NonPooledConnection -EnableException
            $null = $nativeCreated.Add($second)
            $second.ConnectionContext.ConnectionString | Should -BeExactly $first.ConnectionContext.ConnectionString
            $rows = @(Get-NativeConnectedRow -Connection $first)
            $rows.Count | Should -Be 1
            $rows[0].Pooled | Should -BeFalse
            $rows[0].ConnectionObject.Count | Should -Be 2
            [object]::ReferenceEquals($rows[0].ConnectionObject[0], $first) | Should -BeTrue
            [object]::ReferenceEquals($rows[0].ConnectionObject[1], $second) | Should -BeTrue
            $rows[0].SqlInstance | Should -Be $first.Name
            $rows[0].ConnectionType | Should -BeExactly "Microsoft.SqlServer.Management.Smo.Server"
        }
    }

    Context "Cached SqlConnection objects" {
        It "returns a pooled SqlConnection under its data source" {
            $connection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName "dbatoolsci-cnxsc-$random" -SqlConnectionOnly -EnableException
            $null = $nativeCreated.Add($connection)
            (New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $connection.ConnectionString).Pooling | Should -BeTrue
            $rows = @(Get-NativeConnectedRow -Connection $connection)
            $rows.Count | Should -Be 1
            $rows[0].SqlInstance | Should -BeExactly $connection.DataSource
            $rows[0].ConnectionType | Should -BeExactly "Microsoft.Data.SqlClient.SqlConnection"
            $rows[0].Pooled | Should -BeTrue
            (New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $rows[0].ConnectionString).ApplicationName | Should -BeExactly "dbatoolsci-cnxsc-$random"
        }

        It "reports a non-pooled SqlConnection as not pooled" {
            $connection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName "dbatoolsci-cnxscnp-$random" -SqlConnectionOnly -NonPooledConnection -EnableException
            $null = $nativeCreated.Add($connection)
            (New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $connection.ConnectionString).Pooling | Should -BeFalse
            $rows = @(Get-NativeConnectedRow -Connection $connection)
            $rows.Count | Should -Be 1
            $rows[0].ConnectionType | Should -BeExactly "Microsoft.Data.SqlClient.SqlConnection"
            $rows[0].Pooled | Should -BeFalse
        }

        It "reports the fixed failure text for a cache key that is not a connection string" {
            $badKey = "dbatoolsci-cnx-unparseable-$random"
            $fakeConnection = New-Object Microsoft.Data.SqlClient.SqlConnection -ArgumentList "Data Source=dbatoolsci-cnxfake-$random"
            $fakeEntries = New-Object System.Collections.Generic.List[object]
            $fakeEntries.Add($fakeConnection)
            [Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections[$badKey] = $fakeEntries
            try {
                $rows = @(Get-NativeConnectedRow -Connection $fakeConnection)
                $rows.Count | Should -Be 1
                $rows[0].ConnectionString | Should -BeExactly "Failed to mask the connection string"
                $rows[0].SqlInstance | Should -BeExactly "dbatoolsci-cnxfake-$random"
            } finally {
                $null = [Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections.Remove($badKey)
                $fakeConnection.Dispose()
            }
        }
    }

    Context "Commands downstream that change the cache" {
        It "lists every connection cached when it starts, once, while a downstream Connect-DbaInstance adds connections" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName "dbatoolsci-cnxsnap-$random" -EnableException
            $null = $nativeCreated.Add($server)
            $cachedCount = @(Get-DbaConnectedInstance).Count
            $cachedCount | Should -BeGreaterThan 0
            $added = New-Object System.Collections.ArrayList
            try {
                { Get-DbaConnectedInstance | ForEach-Object { $null = $added.Add((Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName ("dbatoolsci-cnxadd-$random-" + $added.Count) -EnableException)) } } | Should -Not -Throw
                $added.Count | Should -Be $cachedCount
                @(Get-DbaConnectedInstance).Count | Should -Be ($cachedCount * 2)
            } finally {
                foreach ($addedServer in $added) { $null = $nativeCreated.Add($addedServer) }
            }
        }

        It "lists every matching connection while a downstream Disconnect-DbaInstance removes each row from the cache" {
            foreach ($number in 1..3) {
                $null = $nativeCreated.Add((Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName "dbatoolsci-cnxrm-$random-$number" -EnableException))
            }
            $removePattern = "*dbatoolsci-cnxrm-$random-*"
            @(Get-DbaConnectedInstance | Where-Object ConnectionString -like $removePattern).Count | Should -Be 3
            $disconnected = New-Object System.Collections.ArrayList
            { Get-DbaConnectedInstance | Where-Object ConnectionString -like $removePattern | ForEach-Object { $null = $disconnected.Add(($PSItem | Disconnect-DbaInstance -Confirm:$false -EnableException)) } } | Should -Not -Throw
            $disconnected.Count | Should -Be 3
            @(Get-DbaConnectedInstance | Where-Object ConnectionString -like $removePattern).Count | Should -Be 0
        }
    }

    Context "Azure SQL Database" {
        It "lists a cached Azure SQL Database connection with its password masked" -Tag NativeChecklist:azure-sqldb {
            $splatAzureConnection = @{
                SqlInstance     = $TestConfig.AzureSqlDbServer
                Database        = $TestConfig.AzureSqlDbName
                SqlCredential   = $TestConfig.AzureSqlDbCred
                ClientName      = "dbatoolsci-cnxazure-$random"
                EnableException = $true
            }
            $azureServer = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureServer = Connect-DbaInstance @splatAzureConnection
                    $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
                    break
                } catch {
                    $azureError = $PSItem.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $null = $nativeCreated.Add($azureServer)
            $key = $azureServer.ConnectionContext.ConnectionString
            $rows = @(Get-NativeConnectedRow -Connection $azureServer)
            $rows.Count | Should -Be 1
            $rows[0].SqlInstance | Should -Be $azureServer.Name
            $rows[0].ConnectionType | Should -BeExactly "Microsoft.SqlServer.Management.Smo.Server"
            $rows[0].Pooled | Should -BeTrue
            $rows[0].ConnectionString | Should -BeExactly (Get-NativeMaskedConnectionString -ConnectionString $key)
            $rows[0].ConnectionString.Contains($TestConfig.AzureSqlDbCred.GetNetworkCredential().Password) | Should -BeFalse
        }
    }
}
