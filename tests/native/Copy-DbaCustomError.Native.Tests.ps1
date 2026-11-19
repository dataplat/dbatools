#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaCustomError",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input.
# Azure SQL Database: Azure SQL Database does not support sp_addmessage user-defined instance messages; refusal is tested below. https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server#t-sql-syntax-not-supported-in-azure-sql-database
# NativeChecklist: sql-login N/A -- the pinned command has SourceSqlCredential and DestinationSqlCredential, not SqlCredential.

Describe "Native Copy-DbaCustomError" -Tag IntegrationTests {
    BeforeAll {
        $source = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $destination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $source.UserDefinedMessages.Refresh()
        $destination.UserDefinedMessages.Refresh()
        do { $messageId = Get-Random -Minimum 700000 -Maximum 1900000000 } while ($messageId -in $source.UserDefinedMessages.ID -or $messageId -in $destination.UserDefinedMessages.ID)
        $english = New-Object Microsoft.SqlServer.Management.Smo.UserDefinedMessage -ArgumentList $source, $messageId, 'us_english', 16, "native quote ' and text"
        $english.Create()
        $french = New-Object Microsoft.SqlServer.Management.Smo.UserDefinedMessage -ArgumentList $source, $messageId, 'French', 16, 'native traduction'
        $french.Create()
        $source.UserDefinedMessages.Refresh()
        $allSourceIds = @($source.UserDefinedMessages.ID | Select-Object -Unique)
        $originalDestinationIds = @($destination.UserDefinedMessages.ID | Select-Object -Unique)
    }
    AfterEach {
        # The before run can ignore ExcludeCustomError and create other source messages.
        # Remove only IDs newly introduced during this fixture; never alter pre-existing destination messages.
        $destination.UserDefinedMessages.Refresh()
        $created = @($destination.UserDefinedMessages | Where-Object { $_.Language -eq 'us_english' -and $_.ID -notin $originalDestinationIds -and $_.ID -in $allSourceIds })
        foreach ($message in $created) {
            $cleanupId = ([int]$message.ID).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $null = $destination.ConnectionContext.ExecuteNonQuery("EXEC master.sys.sp_dropmessage @msgnum = $cleanupId, @lang = N'all';")
        }
    }
    AfterAll {
        $source.UserDefinedMessages.Refresh()
        if ($source.UserDefinedMessages[$messageId, 'us_english']) {
            $cleanupId = ([int]$messageId).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $null = $source.ConnectionContext.ExecuteNonQuery("EXEC master.sys.sp_dropmessage @msgnum = $cleanupId, @lang = N'all';")
        }
    }
    It "honors ExcludeCustomError without an inclusion filter" {
        $copy = @{
            Source = $source
            Destination = $destination
            ExcludeCustomError = $allSourceIds
            Confirm = $false
            EnableException = $true
        }
        @(Copy-DbaCustomError @copy).Count | Should -Be 0
        $destination.UserDefinedMessages.Refresh()
        @($destination.UserDefinedMessages | Where-Object ID -eq $messageId).Count | Should -Be 0
    }
    It "adds a missing translation when the English message already exists" {
        $existing = New-Object Microsoft.SqlServer.Management.Smo.UserDefinedMessage -ArgumentList $destination, $messageId, 'us_english', 16, "native quote ' and text"
        $existing.Create()
        $copy = @{
            Source = $source
            Destination = $destination
            CustomError = $messageId
            Confirm = $false
            EnableException = $true
        }
        $results = @(Copy-DbaCustomError @copy)
        $results.Count | Should -Be 2
        $results[0].Status | Should -Be Skipped
        $results[1].Status | Should -Be Successful
        $destination.UserDefinedMessages.Refresh()
        @($destination.UserDefinedMessages | Where-Object ID -eq $messageId).Count | Should -Be 2
    }
    It "keeps all languages when forcing replacement" {
        $copy = @{
            Source = $source
            Destination = $destination
            CustomError = $messageId
            Confirm = $false
            EnableException = $true
        }
        $existingEnglish = New-Object Microsoft.SqlServer.Management.Smo.UserDefinedMessage -ArgumentList $destination, $messageId, 'us_english', 16, 'old English'
        $existingEnglish.Create()
        $existingFrench = New-Object Microsoft.SqlServer.Management.Smo.UserDefinedMessage -ArgumentList $destination, $messageId, 'French', 16, 'old French'
        $existingFrench.Create()
        $destination.UserDefinedMessages.Refresh()
        @($destination.UserDefinedMessages | Where-Object ID -eq $messageId).Count | Should -Be 2
        $copy.Force = $true
        $results = @(Copy-DbaCustomError @copy)
        $results.Count | Should -Be 2
        @($results | Where-Object Status -ne Successful).Count | Should -Be 0
        $destination.UserDefinedMessages.Refresh()
        @($destination.UserDefinedMessages | Where-Object ID -eq $messageId).Count | Should -Be 2
        $destination.UserDefinedMessages[$messageId, 'us_english'].Text | Should -BeExactly "native quote ' and text"
        # French is an alias; verify the stored translation by its engine message language ID.
        $messageIdSql = ([int]$messageId).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $destination.ConnectionContext.ExecuteScalar("SELECT [text] FROM sys.messages WHERE message_id = $messageIdSql AND language_id = 1036;") | Should -BeExactly 'native traduction'
    }
    It "does not create messages with WhatIf" -Tag NativeChecklist:whatif-confirm {
        $copy = @{
            Source = $source
            Destination = $destination
            CustomError = $messageId
            Force = $true
            WhatIf = $true
            Confirm = $false
        }
        @(Copy-DbaCustomError @copy).Count | Should -Be 0
        $destination.UserDefinedMessages.Refresh()
        @($destination.UserDefinedMessages | Where-Object ID -eq $messageId).Count | Should -Be 0
    }
    It "continues after failed destinations with false switches" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $copy = @{
            Source = $source
            Destination = @('tcp:127.0.0.1,1', $destination)
            CustomError = $messageId
            Force = $false
            EnableException = $false
            Confirm = $false
            WarningVariable = 'warnings'
            WarningAction = 'SilentlyContinue'
        }
        $results = @(Copy-DbaCustomError @copy)
        $results.Count | Should -Be 2
        @($results | Where-Object Status -ne Successful).Count | Should -Be 0
        ($warnings -join ' ') | Should -Match Failure
    }
    It "refuses Azure custom messages and continues to a supported destination" -Tag NativeChecklist:azure-sqldb, NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $azureConnection = @{
            SqlInstance = $TestConfig.AzureSqlDbServer
            Database = $TestConfig.AzureSqlDbName
            SqlCredential = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @azureConnection
                break
            } catch {
                $azureError = $_.Exception
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
            $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $sourceWarnings = @()
            @(Copy-DbaCustomError -Source $azureServer -Destination $destination -CustomError $messageId -EnableException:$false -Confirm:$false -WarningVariable sourceWarnings -WarningAction SilentlyContinue).Count | Should -Be 0
            ($sourceWarnings -join ' ') | Should -Match ([regex]::Escape('Azure SQL Database not supported'))
            { Copy-DbaCustomError -Source $azureServer -Destination $destination -CustomError $messageId -EnableException -Confirm:$false } | Should -Throw '*Azure SQL Database not supported*'
            $azureWarnings = @()
            $copy = @{
                Source = $source
                Destination = @($azureServer, $destination)
                CustomError = $messageId
                EnableException = $false
                Confirm = $false
                WarningVariable = 'azureWarnings'
                WarningAction = 'SilentlyContinue'
            }
            $results = @(Copy-DbaCustomError @copy)
            $results.Count | Should -Be 2
            @($results | Where-Object Status -ne Successful).Count | Should -Be 0
            ($azureWarnings -join ' ') | Should -Match ([regex]::Escape('Azure SQL Database not supported'))
            $destination.UserDefinedMessages.Refresh()
            @($destination.UserDefinedMessages | Where-Object ID -eq $messageId).Count | Should -Be 2
            { Copy-DbaCustomError -Source $source -Destination $azureServer -CustomError $messageId -EnableException -Confirm:$false } | Should -Throw '*Azure SQL Database not supported*'
        } finally {
            if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
        }
    }
    It "throws on connection failure with EnableException" -Tag NativeChecklist:enable-exception {
        $copy = @{
            Source = $source
            Destination = 'tcp:127.0.0.1,1'
            CustomError = $messageId
            EnableException = $true
            Confirm = $false
        }
        { Copy-DbaCustomError @copy } | Should -Throw
    }
}
