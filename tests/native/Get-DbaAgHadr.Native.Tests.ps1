#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgHadr",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- Read-only retrieval; the pinned command does not support ShouldProcess.
Describe "Native Get-DbaAgHadr" -Tag IntegrationTests {
    BeforeAll {
        $nativeHadrBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'
    }

    It "returns the server's HADR state with the instance properties and default view" {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceHadr -EnableException
        $expected = [int]$server.ConnectionContext.ExecuteScalar("SELECT CONVERT(int, SERVERPROPERTY('IsHadrEnabled'))")
        $results = @(Get-DbaAgHadr -SqlInstance $TestConfig.InstanceHadr -EnableException)
        $results.Count | Should -Be 1
        $results[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Server
        $results[0].IsHadrEnabled | Should -Be ([bool]$expected)
        $results[0].ComputerName | Should -Not -BeNullOrEmpty
        $results[0].InstanceName | Should -Not -BeNullOrEmpty
        $results[0].SqlInstance | Should -Not -BeNullOrEmpty
        (@($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ',') | Should -BeExactly 'ComputerName,InstanceName,SqlInstance,IsHadrEnabled'
        # A second call on the same server replaces its notes, as Add-Member -Force does.
        @(Get-DbaAgHadr -SqlInstance $TestConfig.InstanceHadr -EnableException).Count | Should -Be 1
    }

    It "continues after a failed pipeline target with EnableException false" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $warnings = @()
        $results = @(@($nativeHadrBadInstance, $TestConfig.InstanceHadr) | Get-DbaAgHadr -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        $results.Count | Should -Be 1
        $results[0].IsHadrEnabled | Should -BeTrue
        ($warnings -join ' ') | Should -BeLike '*Failure*'
    }

    It "stops at a connection failure with EnableException" -Tag "NativeChecklist:enable-exception" {
        $failure = $null
        try {
            $null = Get-DbaAgHadr -SqlInstance $nativeHadrBadInstance -EnableException
        } catch { $failure = $_ }
        $failure | Should -Not -BeNullOrEmpty
        $failure.FullyQualifiedErrorId | Should -BeLike 'dbatools_Get-DbaAgHadr*'
        $failure.CategoryInfo.Category | Should -Be 'ConnectionError'
    }

    It "reads the SQL-login instance's HADR state with SQL credentials" -Tag "NativeChecklist:sql-login" {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $expected = [int]$server.ConnectionContext.ExecuteScalar("SELECT CONVERT(int, SERVERPROPERTY('IsHadrEnabled'))")
        $results = @(Get-DbaAgHadr -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException)
        $results.Count | Should -Be 1
        $results[0].IsHadrEnabled | Should -Be ([bool]$expected)
        $results[0].SqlInstance | Should -Not -BeNullOrEmpty
    }

    It "rejects the SQL-login instance without credentials" -Tag "NativeChecklist:sql-login" {
        # Pin public/Get-DbaAgHadr.ps1, process block, verbatim:
        # try {
        #     $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        # } catch {
        #     Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        # }
        # Connect-DbaInstance forces its own EnableException, so a failed login throws into this catch: a warning by
        # default, a terminating error under -EnableException.
        # Source-excerpt route: archive/phase2/fable-question-sqllogin-route-general-20261029.txt.
        $warnings = @()
        @(Get-DbaAgHadr -SqlInstance $TestConfig.InstanceSqlLogin -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        ($warnings -join ' ') | Should -BeLike '*Failure*'
        { Get-DbaAgHadr -SqlInstance $TestConfig.InstanceSqlLogin -EnableException } | Should -Throw
    }

    # NativeChecklist: azure-sqldb N/A -- Always On availability groups do not exist in Azure SQL Database; SERVERPROPERTY('IsHadrEnabled') applies to SQL Server only: https://learn.microsoft.com/sql/t-sql/functions/serverproperty-transact-sql
    It "refuses Azure SQL Database instead of reporting an HADR state" {
        $azure = $null
        for ($attempt = 0; $attempt -lt 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $TestConfig.AzureSqlDbName -EnableException
                break
            } catch {
                $transient = $false
                for ($failure = $_.Exception; $failure; $failure = $failure.InnerException) {
                    if ($failure.Number -in @(-2, 40613) -or $failure.Message -match "timed out|timeout") { $transient = $true }
                }
                if (-not $transient -or $attempt -eq 5) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = @()
        @(Get-DbaAgHadr -SqlInstance $azure -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
        { Get-DbaAgHadr -SqlInstance $azure -EnableException } | Should -Throw "*Azure SQL Database not supported*"
    }
}
