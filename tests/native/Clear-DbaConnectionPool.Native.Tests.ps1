#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Clear-DbaConnectionPool",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- The authorized surface has no pipeline-input parameter.
# NativeChecklist: multi-instance-failure N/A -- Clears the current process pools without opening an instance connection.
# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters.
# NativeChecklist: enable-exception N/A -- ClearAllPools has no documented failure case or input to force one; success is exercised with EnableException true and false.
# NativeChecklist: sql-login N/A -- No SqlCredential parameter or instance connection; clears the current process's pools. The Azure test exercises an existing SQL-authenticated pool.
Describe "Clear-DbaConnectionPool native" -Tag IntegrationTests {
    BeforeAll {
        function Test-NativePoolClearing {
            param($Connection, [hashtable]$ConnectionParameters)
            $poolQuery = $Connection.CreateCommand()
            $poolQuery.CommandText = "SELECT @@SPID"
            $observer = $null
            $observerQuery = $null
            try {
                $observerParameters = $ConnectionParameters.Clone()
                $observerParameters.NonPooledConnection = $true
                $observerParameters.ClientName = "native_pool_observer_" + [guid]::NewGuid().ToString('N')
                $observer = Connect-DbaInstance @observerParameters
                $observerBuilder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $observer.ConnectionString
                $observerBuilder.Pooling | Should -BeFalse
                if ($observer.State -eq [System.Data.ConnectionState]::Closed) { $observer.Open() }
                $observerQuery = $observer.CreateCommand()
                $observerQuery.CommandText = 'SELECT COUNT(*) FROM sys.dm_exec_connections WHERE connection_id = @connectionId'
                $observerId = $observerQuery.Parameters.Add('@connectionId', [System.Data.SqlDbType]::UniqueIdentifier)
                $Connection.Open()
                $initialSpid = $poolQuery.ExecuteScalar()
                $initialId = $Connection.ClientConnectionId
                $poolQuery.CommandText = 'SELECT connection_id FROM sys.dm_exec_connections WHERE session_id = @@SPID AND parent_connection_id IS NULL'
                $initialServerId = $poolQuery.ExecuteScalar()
                $initialServerId | Should -BeOfType ([guid])
                $observerId.Value = $initialServerId
                $observerQuery.ExecuteScalar() | Should -Be 1
                $poolQuery.CommandText = 'SELECT @@SPID'
                $Connection.Close()
                $Connection.Open()
                $poolQuery.ExecuteScalar() | Should -Be $initialSpid
                $Connection.ClientConnectionId | Should -Be $initialId
                $Connection.Close()
                @(Clear-DbaConnectionPool -EnableException:$false).Count | Should -Be 0
                $Connection.Open()
                $Connection.ClientConnectionId | Should -Not -Be $initialId
                $observerQuery.ExecuteScalar() | Should -Be 0
            } finally {
                if ($observerQuery) { $observerQuery.Dispose() }
                if ($observer) { $observer.Dispose() }
                $poolQuery.Dispose()
                $Connection.Close()
            }
        }
    }

    Context "Parameters" {
        It "has exactly the common parameters and EnableException" {
            $actualParameters = @((Get-Command Clear-DbaConnectionPool).Parameters.Keys | Sort-Object)
            $expectedParameters = @(@($TestConfig.CommonParameters) + "EnableException" | Sort-Object -Unique)
            Compare-Object $expectedParameters $actualParameters | Should -BeNullOrEmpty
        }
    }

    Context "Pool clearing" {
        It "gives a reopened pooled connection a new SPID" -Tag "NativeChecklist:switch-false" {
            $splatPoolConnection = @{
                SqlInstance = $TestConfig.InstanceSingle
                ClientName = "native_pool_" + [guid]::NewGuid().ToString("N")
                NonPooledConnection = $false
                SqlConnectionOnly = $true
                EnableException = $true
            }
            $poolConnection = Connect-DbaInstance @splatPoolConnection
            try {
                $poolBuilder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $poolConnection.ConnectionString
                $poolBuilder.Pooling | Should -BeTrue
                Test-NativePoolClearing -Connection $poolConnection -ConnectionParameters $splatPoolConnection
                @(Clear-DbaConnectionPool -EnableException).Count | Should -Be 0
            } finally { $poolConnection.Dispose() }
        }

        It "clears a pool connected to Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
            $splatAzureConnection = @{
                SqlInstance = $TestConfig.AzureSqlDbServer
                Database = $TestConfig.AzureSqlDbName
                SqlCredential = $TestConfig.AzureSqlDbCred
                EnableException = $true
            }
            $azureServer = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureServer = Connect-DbaInstance @splatAzureConnection
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
            try {
                $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
                $splatAzureConnection.SqlConnectionOnly = $true
                $splatAzureConnection.NonPooledConnection = $false
                $splatAzureConnection.ClientName = "native_azure_pool_" + [guid]::NewGuid().ToString("N")
                $azurePoolConnection = Connect-DbaInstance @splatAzureConnection
                try { Test-NativePoolClearing -Connection $azurePoolConnection -ConnectionParameters $splatAzureConnection } finally { $azurePoolConnection.Dispose() }
            } finally { $azureServer.ConnectionContext.Disconnect() }
        }
    }
}
