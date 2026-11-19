#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaCustomError",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads $server.UserDefinedMessages.

BeforeAll {
    # One message in English and French under an id of its own. The pinned file's fixed id stays free.
    function New-NativeCustomError {
        param($Server, [int]$Id, [string]$Text)
        foreach ($language in "us_english", "French") {
            $message = New-Object Microsoft.SqlServer.Management.Smo.UserDefinedMessage -ArgumentList $Server, $Id, $language, 16, "$Text ($language)"
            $message.Create()
        }
        $Server.UserDefinedMessages.Refresh()
    }

    function Remove-NativeCustomError {
        param($Server, [int]$Id)
        $cleanupId = $Id.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $null = $Server.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.messages WHERE message_id = $cleanupId) EXEC master.sys.sp_dropmessage @msgnum = $cleanupId, @lang = N'all';")
        $Server.UserDefinedMessages.Refresh()
    }
}

Describe "Get-DbaCustomError native" -Tag IntegrationTests {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $badInstance = "TCP:127.0.0.1,1"
        $displaySet = @("ComputerName", "InstanceName", "SqlInstance", "ID", "Text", "LanguageID", "Language")
        $server.UserDefinedMessages.Refresh()
        do { $messageId = Get-Random -Minimum 700000 -Maximum 1900000000 } while ($messageId -in $server.UserDefinedMessages.ID)
        $messageText = "dbatoolsci custom error $messageId"
        New-NativeCustomError -Server $server -Id $messageId -Text $messageText
    }

    AfterAll {
        Remove-NativeCustomError -Server $server -Id $messageId
    }

    Context "Custom errors" {
        It "returns one decorated SMO message per language with the pinned default view" {
            $results = @(Get-DbaCustomError -SqlInstance $server -EnableException | Where-Object ID -eq $messageId)
            $results.Count | Should -Be 2
            foreach ($result in $results) {
                $result | Should -BeOfType Microsoft.SqlServer.Management.Smo.UserDefinedMessage
                $result.ComputerName | Should -Be $server.ComputerName
                $result.InstanceName | Should -Be $server.ServiceName
                $result.SqlInstance | Should -Be $server.DomainInstanceName
                $result.Severity | Should -Be 16
                @($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Be $displaySet
            }
            ($results.LanguageID | Sort-Object) | Should -Be @(1033, 1036)
            ($results | Where-Object LanguageID -eq 1033).Text | Should -BeExactly "$messageText (us_english)"
            ($results | Where-Object LanguageID -eq 1036).Text | Should -BeExactly "$messageText (French)"
        }

        It "connects by name as well as through a server object" {
            $results = @(Get-DbaCustomError -SqlInstance $TestConfig.InstanceSingle -EnableException | Where-Object ID -eq $messageId)
            $results.Count | Should -Be 2
        }
    }

    Context "Several instances" {
        It "queries every piped instance, decorating the same messages again" -Tag NativeChecklist:pipeline-multiple {
            $results = @(@($server, $server) | Get-DbaCustomError -EnableException | Where-Object ID -eq $messageId)
            $results.Count | Should -Be 4
            foreach ($result in $results) {
                $result.SqlInstance | Should -Be $server.DomainInstanceName
            }
        }

        It "warns 'Failure' for an instance it cannot connect to and still reads the next one" -Tag NativeChecklist:multi-instance-failure {
            $connectWarnings = @()
            $results = @(Get-DbaCustomError -SqlInstance $badInstance, $server -WarningVariable connectWarnings -WarningAction SilentlyContinue | Where-Object ID -eq $messageId)
            $connectWarnings.Count | Should -Be 1
            "$connectWarnings" | Should -BeLike "*Failure*"
            $results.Count | Should -Be 2
        }

        It "stops at the instance it cannot connect to under -EnableException, with category ConnectionError" -Tag NativeChecklist:enable-exception {
            $seen = New-Object System.Collections.ArrayList
            $connectCaught = $null
            try {
                Get-DbaCustomError -SqlInstance $badInstance, $server -EnableException | ForEach-Object { $null = $seen.Add($PSItem) }
            } catch {
                $connectCaught = $PSItem
            }
            $connectCaught | Should -Not -BeNullOrEmpty
            $connectCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCustomError*"
            $connectCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $seen.Count | Should -Be 0
        }

        It "keeps the output of an earlier instance when -EnableException stops at a later one" -Tag NativeChecklist:enable-exception {
            $seen = New-Object System.Collections.ArrayList
            $connectCaught = $null
            try {
                Get-DbaCustomError -SqlInstance $server, $badInstance -EnableException | ForEach-Object { $null = $seen.Add($PSItem) }
            } catch {
                $connectCaught = $PSItem
            }
            $connectCaught | Should -Not -BeNullOrEmpty
            @($seen | Where-Object ID -eq $messageId).Count | Should -Be 2
        }

        It "warns and moves on for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            $falseWarnings = @()
            $results = @(Get-DbaCustomError -SqlInstance $badInstance, $server -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue | Where-Object ID -eq $messageId)
            $falseWarnings.Count | Should -Be 1
            $results.Count | Should -Be 2
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $sqlLoginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -EnableException
            # sqlwhale22 is shared by the parallel lanes: an id of its own, removed afterwards.
            $loginServer.UserDefinedMessages.Refresh()
            do { $loginMessageId = Get-Random -Minimum 700000 -Maximum 1900000000 } while ($loginMessageId -in $loginServer.UserDefinedMessages.ID)
            New-NativeCustomError -Server $loginServer -Id $loginMessageId -Text "dbatoolsci custom error $loginMessageId"
        }

        AfterAll {
            Remove-NativeCustomError -Server $loginServer -Id $loginMessageId
        }

        # The missing-credential assertions follow the pinned code quoted below instead of a -Baseline run
        # (watchman 49f13ebb): no commit can run the pinned function, because the base already ships the compiled
        # Get-DbaCustomError cmdlet and the pin predates src/ and cannot be built.
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaCustomError.ps1:77-82
        #         foreach ($instance in $SqlInstance) {
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        #
        # Without the credential the connect fails and Stop-Function -Continue warns "Failure" and moves on; under
        # -EnableException the same Stop-Function throws with category ConnectionError.
        It "works with -SqlCredential" {
            $loginWarnings = @()
            $results = @(Get-DbaCustomError -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -EnableException -WarningVariable loginWarnings | Where-Object ID -eq $loginMessageId)
            $loginWarnings.Count | Should -Be 0
            $results.Count | Should -Be 2
        }

        It "fails cleanly without the credential: a warning and no output" {
            $noLoginWarnings = @()
            $results = @(Get-DbaCustomError -SqlInstance $loginInstance -WarningVariable noLoginWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($noLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned Stop-Function does" {
            $noLoginCaught = $null
            try {
                $null = Get-DbaCustomError -SqlInstance $loginInstance -EnableException
            } catch {
                $noLoginCaught = $PSItem
            }
            $noLoginCaught | Should -Not -BeNullOrEmpty
            $noLoginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # User-defined messages do not exist in Azure SQL Database: sp_addmessage and sys.messages apply to SQL Server
            # (https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-addmessage-transact-sql,
            # https://learn.microsoft.com/sql/t-sql/language-elements/raiserror-transact-sql).
            $azure = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
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
        }

        AfterAll {
            if ($azure) { $azure.ConnectionContext.Disconnect() }
        }

        It "warns that Azure SQL Database is not supported and returns nothing" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureWarnings = @()
            @(Get-DbaCustomError -SqlInstance $azure -WarningAction SilentlyContinue -WarningVariable azureWarnings).Count | Should -Be 0
            ($azureWarnings -join " ") | Should -Match "Azure SQL Database not supported"
        }

        It "throws that Azure SQL Database is not supported under -EnableException" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            { Get-DbaCustomError -SqlInstance $azure -EnableException } | Should -Throw "*Azure SQL Database not supported*"
        }
    }
}
