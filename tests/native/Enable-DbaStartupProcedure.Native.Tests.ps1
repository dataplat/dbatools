#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Enable-DbaStartupProcedure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Enable-DbaStartupProcedure" -Tag IntegrationTests {
    BeforeAll {
        function New-NativeStartupConnection($instance, $credential) {
            $builder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder
            $builder['Data Source'] = [string]$instance
            $builder['Initial Catalog'] = 'master'
            $builder['Encrypt'] = $false
            $builder['TrustServerCertificate'] = $true
            $builder['Connect Timeout'] = 15
            if ($credential) {
                $builder['User ID'] = $credential.UserName
                $builder['Password'] = $credential.GetNetworkCredential().Password
            } else {
                $builder['Integrated Security'] = $true
            }
            $connection = New-Object Microsoft.Data.SqlClient.SqlConnection -ArgumentList $builder.ConnectionString
            $connection.Open()
            return $connection
        }
        function Invoke-NativeStartupSql($connection, $sql) {
            $query = $connection.CreateCommand()
            try {
                $query.CommandText = $sql
                for ($attempt = 0; $attempt -lt 5; $attempt++) {
                    try { return $query.ExecuteScalar() } catch {
                        $errorException = $_.Exception
                        $deadlock = $false
                        while ($errorException) {
                            if ($errorException.Number -eq 1205) { $deadlock = $true }
                            $errorException = $errorException.InnerException
                        }
                        if (-not $deadlock -or $attempt -eq 4) { throw }
                        Start-Sleep -Milliseconds 200
                    }
                }
            } finally { $query.Dispose() }
        }
        $startupConnection = New-NativeStartupConnection $TestConfig.InstanceSingle $null
        $startupNames = @(1..8 | ForEach-Object { 'native_startup_' + [guid]::NewGuid().ToString('N') })
        $startupCreated = New-Object System.Collections.ArrayList
        foreach ($name in $startupNames) {
            $null = Invoke-NativeStartupSql $startupConnection "CREATE PROCEDURE [dbo].[$name] AS SELECT 1"
            $null = $startupCreated.Add($name)
        }
    }

    AfterAll {
        if ($startupConnection) {
            try {
                foreach ($name in $startupCreated) {
                    $null = Invoke-NativeStartupSql $startupConnection "DROP PROCEDURE [dbo].[$name]"
                }
            } finally { $startupConnection.Dispose() }
        }
    }

    It "enables every named procedure and emits their results in input order" -Tag "NativeChecklist:switch-false" {
        $names = @($startupNames[0], $startupNames[1])
        $output = @(Enable-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSingle -StartupProcedure ($names | ForEach-Object { '[dbo].[' + $_ + ']' }) -WhatIf:$false -Confirm:$false -EnableException)
        $output.Count | Should -Be 2
        for ($i = 0; $i -lt 2; $i++) {
            $output[$i].Name | Should -BeExactly $names[$i]
            $output[$i].Schema | Should -BeExactly 'dbo'
            $output[$i].Action | Should -BeExactly 'Enable'
            $output[$i].Status | Should -BeTrue
            $output[$i].Note | Should -BeExactly 'Enable succeded'
            $output[$i].Database | Should -BeExactly 'master'
            $output[$i].ComputerName | Should -Not -BeNullOrEmpty
            $name = $names[$i]
            (Invoke-NativeStartupSql $startupConnection "SELECT is_auto_executed FROM sys.procedures WHERE name = N'$name'") | Should -BeTrue
        }
    }

    It "returns a skipped result without changing the procedure under WhatIf" -Tag "NativeChecklist:whatif-confirm" {
        $name = $startupNames[6]
        $output = Enable-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSingle -StartupProcedure ('dbo.' + $name) -WhatIf -Confirm:$false -EnableException
        $output.Status | Should -BeFalse
        $output.Note | Should -BeExactly 'Enable skipped'
        (Invoke-NativeStartupSql $startupConnection "SELECT is_auto_executed FROM sys.procedures WHERE name = N'$name'") | Should -BeFalse
    }

    It "preserves both pipeline records around a failed middle connection" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $name = $startupNames[4]
        $badInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'
        $warnings = @()
        $output = @(@($TestConfig.InstanceSingle, $badInstance, $TestConfig.InstanceSingle) | Enable-DbaStartupProcedure -StartupProcedure ('dbo.' + $name) -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        $output.Count | Should -Be 2
        $output[0].Name | Should -BeExactly $name
        $output[1].Name | Should -BeExactly $name
        $output[1].Note | Should -BeExactly 'Action Enable already performed'
        $warnings | Should -Not -BeNullOrEmpty
        (Invoke-NativeStartupSql $startupConnection "SELECT is_auto_executed FROM sys.procedures WHERE name = N'$name'") | Should -BeTrue
    }

    It "retains earlier output when EnableException stops at a missing procedure" -Tag "NativeChecklist:enable-exception" {
        $seen = New-Object System.Collections.ArrayList
        $failure = $null
        $first = $startupNames[7]
        $last = $startupNames[3]
        try {
            Enable-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSingle -StartupProcedure @(('dbo.' + $first), 'missing.NoSuchProcedure', ('dbo.' + $last)) -Confirm:$false -EnableException | ForEach-Object { $null = $seen.Add($_) }
        } catch { $failure = $_ }
        $seen.Count | Should -Be 1
        $seen[0].Name | Should -BeExactly $first
        $failure | Should -Not -BeNullOrEmpty
        $failure.CategoryInfo.Category | Should -Be 'InvalidData'
        (Invoke-NativeStartupSql $startupConnection "SELECT is_auto_executed FROM sys.procedures WHERE name = N'$last'") | Should -BeFalse
    }

    It "supports the documented simple procedure name" {
        $name = $startupNames[5]
        $output = Enable-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSingle -StartupProcedure $name -Confirm:$false -EnableException
        $output.Name | Should -BeExactly $name
        $output.Status | Should -BeTrue
        (Invoke-NativeStartupSql $startupConnection "SELECT is_auto_executed FROM sys.procedures WHERE name = N'$name'") | Should -BeTrue
    }

    It "enables a unique startup procedure using SQL authentication and rejects omitted credentials" -Tag "NativeChecklist:sql-login" {
        $name = 'native_startup_login_' + [guid]::NewGuid().ToString('N')
        $connection = New-NativeStartupConnection $TestConfig.InstanceSqlLogin $TestConfig.SqlLoginCred
        $created = $false
        try {
            $null = Invoke-NativeStartupSql $connection "CREATE PROCEDURE [dbo].[$name] AS SELECT 1"
            $created = $true
            $output = Enable-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -StartupProcedure ('dbo.' + $name) -Confirm:$false -EnableException
            $output.Status | Should -BeTrue
            (Invoke-NativeStartupSql $connection "SELECT is_auto_executed FROM sys.procedures WHERE name = N'$name'") | Should -BeTrue
            $warnings = @()
            @(Enable-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSqlLogin -StartupProcedure ('dbo.' + $name) -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings | Should -Not -BeNullOrEmpty
            # Pin: try { Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential }
            # catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            # Connect-DbaInstance throws by default; this command's catch uses its own EnableException.
            { Enable-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSqlLogin -StartupProcedure ('dbo.' + $name) -Confirm:$false -EnableException } | Should -Throw
        } finally {
            try { if ($created) { $null = Invoke-NativeStartupSql $connection "DROP PROCEDURE [dbo].[$name]" } }
            finally { $connection.Dispose() }
        }
    }

    It "refuses Azure SQL Database before enabling a startup procedure" -Tag "NativeChecklist:azure-sqldb" {
        $azure = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database master -EnableException
                break
            } catch {
                $errorException = $_.Exception
                $resuming = $false
                while ($errorException) {
                    if ($errorException.Number -in 40613, -2 -or $errorException -is [System.TimeoutException] -or $errorException.Message -match 'timed out|timeout|wait operation') { $resuming = $true }
                    $errorException = $errorException.InnerException
                }
                if (-not $resuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azure.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
        $name = 'native_startup_azure_' + [guid]::NewGuid().ToString('N')
        $created = $false
        try {
            $azure.ConnectionContext.ExecuteNonQuery("CREATE PROCEDURE [dbo].[$name] AS SELECT 1")
            $created = $true
            [int]$azure.ConnectionContext.ExecuteScalar("SELECT OBJECTPROPERTY(OBJECT_ID(N'dbo.$name'), 'ExecIsStartup')") | Should -Be 0
            $warnings = @()
            @(Enable-DbaStartupProcedure -SqlInstance $azure -StartupProcedure ('dbo.' + $name) -Confirm:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            ($warnings -join ' ') | Should -Match 'Azure SQL Database not supported'
            { Enable-DbaStartupProcedure -SqlInstance $azure -StartupProcedure ('dbo.' + $name) -Confirm:$false -EnableException } | Should -Throw '*Azure SQL Database not supported*'
            [int]$azure.ConnectionContext.ExecuteScalar("SELECT OBJECTPROPERTY(OBJECT_ID(N'dbo.$name'), 'ExecIsStartup')") | Should -Be 0
        } finally {
            try { if ($created) { $azure.ConnectionContext.ExecuteNonQuery("DROP PROCEDURE [dbo].[$name]") } }
            finally { $azure.ConnectionContext.Disconnect() }
        }
    }
}
