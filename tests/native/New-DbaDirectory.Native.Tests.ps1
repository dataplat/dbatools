#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaDirectory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- The pinned parameters take no pipeline input.
# NativeChecklist: platform cross-platform -- The SQL Server service creates the directory, independently of the client OS.

Describe "New-DbaDirectory on the SQL Server service account" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $root = Join-Path $TestConfig.Temp ("dbatoolsci_directory_" + [guid]::NewGuid().ToString("N"))
        $null = New-Item -ItemType Directory -Path $root -ErrorAction Stop
    }
    AfterAll {
        if ($root -and [IO.Directory]::Exists($root)) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
        }
    }

    It "previews the creation and then creates the directory when confirmation is disabled" -Tag "NativeChecklist:whatif-confirm", "NativeChecklist:switch-false" {
        $path = Join-Path $root "normal"
        @(New-DbaDirectory -SqlInstance $instance -Path $path -WhatIf).Count | Should -Be 0
        [IO.Directory]::Exists($path) | Should -BeFalse
        $row = New-DbaDirectory -SqlInstance $instance -Path $path -Confirm:$false -EnableException:$false
        @($row.PSObject.Properties.Name) | Should -Be @("Server", "Path", "Created")
        $row.Server.GetType().Name | Should -BeExactly "DbaInstanceParameter"
        $row.Server.ToString() | Should -Be $instance
        $row.Path | Should -BeExactly $path
        $row.Created | Should -BeTrue
        [IO.Directory]::Exists($path) | Should -BeTrue
    }

    It "keeps an apostrophe in the directory name and recognizes it on the next instance" {
        $path = Join-Path $root "O'Brien"
        $rows = @(New-DbaDirectory -SqlInstance $instance, $instance -Path $path -Confirm:$false -EnableException:$false -WarningVariable existing -WarningAction SilentlyContinue)
        $rows.Count | Should -Be 1
        $rows[0].Path | Should -BeExactly $path
        $rows[0].Created | Should -BeTrue
        [IO.Directory]::Exists($path) | Should -BeTrue
        [IO.Directory]::Exists((Join-Path $root "O''Brien")) | Should -BeFalse
        @($existing).Count | Should -Be 1
        $existing[0].Message | Should -Match ([regex]::Escape("$path already exists"))
    }

    It "recognizes an existing file as well as an existing directory" {
        $filePath = Join-Path $root "occupied.txt"
        [IO.File]::WriteAllText($filePath, "owned test file")
        $rows = @(New-DbaDirectory -SqlInstance $instance -Path $filePath -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        $rows.Count | Should -Be 0
        @($warnings).Count | Should -Be 1
        $warnings[0].Message | Should -Match ([regex]::Escape("$filePath already exists"))
        [IO.File]::ReadAllText($filePath) | Should -BeExactly "owned test file"
    }

    It "warns and continues after a refused login and stops under EnableException" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $path = Join-Path $root "after"
        $rows = @(New-DbaDirectory -SqlInstance $TestConfig.InstanceSqlLogin, $instance -Path $path -Confirm:$false -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
        $rows.Count | Should -Be 1
        $rows[0].Server.ToString() | Should -Be $instance
        $rows[0].Created | Should -BeTrue
        $warnings[0].Message | Should -Match "Failure"
        $stopped = Join-Path $root "stopped"
        { New-DbaDirectory -SqlInstance $TestConfig.InstanceSqlLogin, $instance -Path $stopped -Confirm:$false -EnableException } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_New-DbaDirectory*"
        [IO.Directory]::Exists($stopped) | Should -BeFalse
    }

    It "creates the directory with the SQL login and reports a refused connection without it" -Tag "NativeChecklist:sql-login" {
        $deniedPath = Join-Path $root "no_login"
        $missing = @(New-DbaDirectory -SqlInstance $TestConfig.InstanceSqlLogin -Path $deniedPath -Confirm:$false -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
        $missing.Count | Should -Be 0
        $warnings[0].Message | Should -Match "Login failed" -Because "the SQL-login service on $($TestConfig.InstanceSqlLogin) denies the uncredentialed call for $deniedPath"
        [IO.Directory]::Exists($deniedPath) | Should -BeFalse
        $path = Join-Path $root "sql_login"
        $row = New-DbaDirectory -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -Path $path -Confirm:$false -EnableException -WarningVariable createWarnings
        $row.Created | Should -BeTrue -Because "the SQL-login service on $($TestConfig.InstanceSqlLogin) should report creating $path (warnings: $createWarnings)"
        $row.Path | Should -BeExactly $path
        $observed = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -Database master -Query "EXEC master.dbo.xp_fileexist @path" -SqlParameter @{ path = $path } -EnableException
        $observed."File is a Directory" | Should -Be 1 -Because "the SQL-login service on $($TestConfig.InstanceSqlLogin) should see $path on the server"
        [IO.Directory]::Exists($path) | Should -BeTrue -Because "the workstation should see $path after the SQL-login service on $($TestConfig.InstanceSqlLogin) created it"
    }

    It "reports a creation failure beneath an existing file and throws under EnableException" {
        $filePath = Join-Path $root "parent.txt"
        [IO.File]::WriteAllText($filePath, "owned test file")
        $path = Join-Path $filePath "child"
        $row = New-DbaDirectory -SqlInstance $instance -Path $path -Confirm:$false -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue
        $row.Path | Should -BeExactly $path
        $row.Created | Should -BeFalse
        $warnings[0].Message | Should -Match "Failure"
        { New-DbaDirectory -SqlInstance $instance -Path $path -Confirm:$false -EnableException } | Should -Throw
        [IO.Directory]::Exists($path) | Should -BeFalse
    }
}

Describe "New-DbaDirectory on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $connect = @{
            SqlInstance = $TestConfig.AzureSqlDbServer
            Database = $TestConfig.AzureSqlDbName
            SqlCredential = $TestConfig.AzureSqlDbCred
            NonPooledConnection = $true
            ErrorAction = "Stop"
        }
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance @connect
                break
            } catch {
                $resuming = $false
                for ($failure = $PSItem.Exception; $failure; $failure = $failure.InnerException) {
                    if ($failure.Number -in 40613, -2 -or $failure -is [System.TimeoutException] -or $failure.Message -match "timeout|timed out") { $resuming = $true }
                }
                if (-not $resuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }
    AfterAll {
        if ($azure) { $azure.ConnectionContext.Disconnect() }
    }
    It "refuses an Azure SQL Database without attempting to create a directory" -Tag "NativeChecklist:azure-sqldb" {
        $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $rows = @(New-DbaDirectory -SqlInstance $azure -Path "dbatoolsci_directory_preview" -WhatIf -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        $rows.Count | Should -Be 0
        "$warnings" | Should -BeLike "*Azure SQL Database not supported*"
        { New-DbaDirectory -SqlInstance $azure -Path "dbatoolsci_directory_preview" -WhatIf -EnableException } | Should -Throw "*Azure SQL Database not supported*"
    }
}
