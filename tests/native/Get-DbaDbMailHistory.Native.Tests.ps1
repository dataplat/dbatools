#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbMailHistory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads msdb.

Describe "Get-DbaDbMailHistory native" -Tag IntegrationTests {
    BeforeAll {
        # Unique per leg and run; every assertion reads only this run's rows, and AfterAll removes them.
        $nativeSuffix = [Guid]::NewGuid().ToString("N").Substring(0, 12)
        $nativePrefix = "dbatoolsci_mailhistory_$($nativeSuffix)_"
        $profileName = "$($nativePrefix)profile"
        $removedName = "$($nativePrefix)removed"
        $lowLogin = "$($nativePrefix)low"
        $lowPassword = "Ml!" + [Guid]::NewGuid().ToString("N")
        $unicodeSubject = "$($nativePrefix)" + [string][char]0x65E5 + [string][char]0x672C + [string][char]0x8A9E
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection

        $mailSql = "INSERT INTO msdb.dbo.sysmail_mailitems (profile_id, recipients, copy_recipients, blind_copy_recipients, subject, from_address, reply_to, body, body_format, importance, sensitivity, file_attachments, attachment_encoding, query, execute_query_database, attach_query_result_as_file, query_result_header, query_result_width, query_result_separator, exclude_query_output, append_query_error, send_request_date, send_request_user, sent_account_id, sent_status, sent_date, last_mod_date, last_mod_user) VALUES ({0}, 'native@dbatools.io', NULL, NULL, N'{1}', NULL, NULL, 'native body', 'TEXT', 'NORMAL', 'NORMAL', NULL, 'MIME', NULL, NULL, 0, 1, 256, '', 0, 0, '{2}', 'lab\native', 1, {3}, '{2}', '{2}', 'sa');"

        $null = $nativeServer.ConnectionContext.ExecuteNonQuery("INSERT INTO msdb.dbo.sysmail_profile (name, description, last_mod_datetime, last_mod_user) VALUES (N'$profileName', N'native', '2018-12-09T08:00:32.700', N'sa');")
        $profileId = [int]$nativeServer.ConnectionContext.ExecuteScalar("SELECT profile_id FROM msdb.dbo.sysmail_profile WHERE name = N'$profileName';")
        $null = $nativeServer.ConnectionContext.ExecuteNonQuery("EXECUTE msdb.dbo.sysmail_add_profile_sp @profile_name = N'$removedName', @description = N'native';")
        $removedId = [int]$nativeServer.ConnectionContext.ExecuteScalar("SELECT profile_id FROM msdb.dbo.sysmail_profile WHERE name = N'$removedName';")

        $fixture = @(
            ($mailSql -f $profileId, "$($nativePrefix)sent", "2026-01-01T10:00:00.000", 1)
            ($mailSql -f $profileId, "$($nativePrefix)failed", "2026-01-01T10:00:01.000", 2)
            ($mailSql -f $profileId, "$($nativePrefix)unsent", "2026-01-01T10:00:02.000", 0)
            ($mailSql -f $profileId, "$($nativePrefix)retrying", "2026-01-01T10:00:03.000", 3)
            ($mailSql -f $profileId, $unicodeSubject, "2026-01-01T10:00:04.000", 1)
            ($mailSql -f $removedId, "$($nativePrefix)profile removed", "2026-01-01T10:00:05.000", 1)
        )
        foreach ($statement in $fixture) {
            $null = $nativeServer.ConnectionContext.ExecuteNonQuery($statement)
        }
        # A removed profile leaves its mail in sysmail_allitems.
        $null = $nativeServer.ConnectionContext.ExecuteNonQuery("EXECUTE msdb.dbo.sysmail_delete_profile_sp @profile_name = N'$removedName';")

        # A login that connects but cannot read msdb's mail tables, for the failed read.
        $null = $nativeServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$lowLogin] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        $lowCredential = New-Object System.Management.Automation.PSCredential($lowLogin, (ConvertTo-SecureString $lowPassword -AsPlainText -Force))
        $lowServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $lowCredential -NonPooledConnection

        function Get-NativeOwnRow {
            param($Rows)
            @($Rows | Where-Object Subject -like "$nativePrefix*")
        }
    }

    AfterAll {
        if ($lowServer) {
            $lowServer.ConnectionContext.Disconnect()
        }
        $null = $nativeServer.ConnectionContext.ExecuteNonQuery("DELETE msdb.dbo.sysmail_mailitems WHERE profile_id IN ($profileId, $removedId);")
        $null = $nativeServer.ConnectionContext.ExecuteNonQuery("DELETE msdb.dbo.sysmail_profile WHERE profile_id IN ($profileId, $removedId);")
        for ($attempt = 0; $attempt -lt 10; $attempt++) {
            try {
                $sessions = $nativeServer.ConnectionContext.ExecuteWithResults("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowLogin'").Tables[0].Rows
                foreach ($row in $sessions) {
                    $null = $nativeServer.ConnectionContext.ExecuteNonQuery("KILL $($row.session_id);")
                }
                $null = $nativeServer.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$lowLogin') IS NOT NULL DROP LOGIN [$lowLogin];")
                break
            } catch {
                if ($attempt -eq 9) { throw }
                Start-Sleep -Seconds 1
            }
        }
        $nativeServer.ConnectionContext.Disconnect()
    }

    Context "Rows" {
        It "returns the data rows with the pinned columns and display set" {
            $rows = @(Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer) | Where-Object Subject -eq "$($nativePrefix)sent")
            $rows.Count | Should -Be 1
            $row = $rows[0]
            $row.GetType().FullName | Should -BeExactly "System.Data.DataRow"
            ($row.PSObject.TypeNames -join ",") | Should -BeExactly "System.Data.DataRow,System.Object"
            (@($row.Table.Columns.ColumnName) -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,MailItemId,ProfileId,Profile,Recipients,CopyRecipients,BlindCopyRecipients,Subject,Body,BodyFormat,Importance,Sensitivity,FileAttachments,AttachmentEncoding,Query,ExecuteQueryDatabase,AttachQueryResultAsFile,QueryResultHeader,QueryResultWidth,QueryResultSeparator,ExcludeQueryOutput,AppendQueryError,SendRequestDate,SendRequestUser,SentAccountId,SentStatus,SentDate,LastModDate,LastModUser"
            (@($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Profile,Recipients,CopyRecipients,BlindCopyRecipients,Subject,Importance,Sensitivity,FileAttachments,AttachmentEncoding,SendRequestDate,SendRequestUser,SentStatus,SentDate"
        }

        It "reads the columns of a message" {
            $row = @(Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer) | Where-Object Subject -eq "$($nativePrefix)sent")[0]
            "$($row.ComputerName)" | Should -Not -BeNullOrEmpty
            "$($row.InstanceName)" | Should -Not -BeNullOrEmpty
            "$($row.SqlInstance)" | Should -Not -BeNullOrEmpty
            $row.Profile | Should -BeExactly $profileName
            $row.ProfileId | Should -Be $profileId
            $row.Recipients | Should -BeExactly "native@dbatools.io"
            $row.CopyRecipients | Should -BeOfType [System.DBNull]
            $row.Body | Should -BeExactly "native body"
            $row.BodyFormat | Should -BeExactly "TEXT"
            $row.AttachQueryResultAsFile | Should -BeFalse
            $row.QueryResultHeader | Should -BeTrue
            $row.QueryResultWidth | Should -Be 256
            $row.SendRequestDate | Should -Be ([datetime]"2026-01-01T10:00:00")
            $row.SendRequestUser | Should -BeExactly "lab\native"
            $row.SentStatus | Should -BeExactly "Sent"
            $row.LastModUser | Should -BeExactly "sa"
        }

        It "keeps a subject outside the server code page" {
            $rows = @(Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer) | Where-Object Subject -ceq $unicodeSubject)
            $rows.Count | Should -Be 1
        }
    }

    Context "-Status" {
        It "keeps the named status" {
            foreach ($status in "Sent", "Failed", "Unsent", "Retrying") {
                $rows = @(Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer -Status $status))
                $rows.Count | Should -BeGreaterThan 0
                ($rows.SentStatus | Select-Object -Unique) | Should -BeExactly $status
            }
        }

        It "takes the status without regard to case" {
            (Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer -Status FAILED)).Subject | Should -BeExactly "$($nativePrefix)failed"
        }

        It "refuses a value outside the set through the binder" {
            { Get-DbaDbMailHistory -SqlInstance $nativeServer -Status Nope } | Should -Throw -ErrorId "ParameterArgumentValidationError*"
            { Get-DbaDbMailHistory -SqlInstance $nativeServer -Status "" } | Should -Throw -ErrorId "ParameterArgumentValidationError*"
            { Get-DbaDbMailHistory -SqlInstance $nativeServer -Status $null } | Should -Throw -ErrorId "ParameterArgumentValidationError*"
        }
    }

    Context "-Since" {
        It "keeps mail requested at or after the date" {
            $rows = @(Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer -Since ([datetime]"2026-01-01T10:00:03")))
            ($rows.Subject | Sort-Object) -contains "$($nativePrefix)retrying" | Should -BeTrue
            ($rows.Subject) -contains "$($nativePrefix)unsent" | Should -BeFalse
        }

        It "reads a date string by the invariant culture, as the pinned [datetime] parameter does" {
            $savedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("de-DE")
                (Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer -Since "12/31/2025")).Count | Should -BeGreaterThan 0
            } finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $savedCulture
            }
        }

        It "compares the clock value and ignores its Kind" {
            $utcSince = [datetime]::SpecifyKind([datetime]"2026-01-01T10:00:03", [System.DateTimeKind]::Utc)
            ((Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer -Since $utcSince)).Subject) -contains "$($nativePrefix)retrying" | Should -BeTrue
        }

        It "returns nothing after the last mail" {
            (Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer -Since "2036-01-01")).Count | Should -Be 0
        }

        It "applies -Since and -Status together" {
            (Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer -Since ([datetime]"2026-01-01T10:00:02") -Status Unsent)).Subject | Should -BeExactly "$($nativePrefix)unsent"
            (Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer -Since ([datetime]"2026-01-01T10:00:03") -Status Unsent)).Count | Should -Be 0
        }
    }

    Context "The debug stream" {
        It "reports the filtered query, with the line ends of the pinned source" {
            $DebugPreference = "Continue"
            $stream = @(Get-DbaDbMailHistory -SqlInstance $nativeServer -Since "2036-01-01" -Status FAILED 5>&1)
            $DebugPreference = "SilentlyContinue"
            $query = @($stream | Where-Object { $PSItem -is [System.Management.Automation.DebugRecord] -and $PSItem.Message.Contains("sysmail_allitems") })
            $query.Count | Should -Be 1
            $query[0].Message.Contains("ON a.profile_id = p.profile_id WHERE send_request_date >= CONVERT(datetime,'2036-01-01T00:00:00',126) AND LOWER(sent_status) IN ('failed')") | Should -BeTrue
            $query[0].Message.Contains("`r") | Should -BeFalse
            $query[0].Message.Contains("`n") | Should -BeTrue
        }
    }

    Context "Instances" {
        It "does nothing without an instance" {
            $quietWarnings = @()
            @(Get-DbaDbMailHistory -WarningVariable +quietWarnings).Count | Should -Be 0
            @(Get-DbaDbMailHistory -SqlInstance $null -WarningVariable +quietWarnings).Count | Should -Be 0
            @(Get-DbaDbMailHistory -SqlInstance @() -WarningVariable +quietWarnings).Count | Should -Be 0
            @($null | Get-DbaDbMailHistory -WarningVariable +quietWarnings).Count | Should -Be 0
            @($quietWarnings).Count | Should -Be 0
        }

        It "warns for a null element and goes on" -Tag "NativeChecklist:multi-instance-failure" {
            $nullWarnings = @()
            $rows = @(Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $null, $TestConfig.InstanceSingle -Status FAILED -WarningAction SilentlyContinue -WarningVariable nullWarnings))
            $rows.Count | Should -Be 1
            ($nullWarnings -join " ") | Should -BeLike "*Failure | Cannot bind argument to parameter 'SqlInstance' because it is null."
        }

        It "refuses an empty instance name through the binder" {
            { Get-DbaDbMailHistory -SqlInstance "" } | Should -Throw -ErrorId "ParameterArgumentTransformationError*"
        }

        It "reads each instance of an array and of the pipeline" -Tag "NativeChecklist:pipeline-multiple" {
            (Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer, $nativeServer -Status FAILED)).Count | Should -Be 2
            (Get-NativeOwnRow -Rows ($nativeServer, $nativeServer | Get-DbaDbMailHistory -Status FAILED)).Count | Should -Be 2
        }
    }

    Context "Failed connection" {
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $connectWarnings = @()
            $rows = @(Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance "TCP:127.0.0.1,1", $nativeServer -Status FAILED -WarningAction SilentlyContinue -WarningVariable connectWarnings))
            $rows.Count | Should -Be 1
            @($connectWarnings).Count | Should -Be 1
            ($connectWarnings -join " ") | Should -BeLike "*Failure | *"
        }

        It "throws the original fault under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $thrown = $null
            try {
                $null = Get-DbaDbMailHistory -SqlInstance "TCP:127.0.0.1,1" -EnableException
            } catch {
                $thrown = $PSItem
            }
            $thrown | Should -Not -BeNullOrEmpty
            $thrown.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMailHistory*"
            $thrown.CategoryInfo.Category.ToString() | Should -BeExactly "ConnectionError"
            "$($thrown.TargetObject)" | Should -BeExactly "TCP:127.0.0.1,1"
        }

        It "-EnableException:`$false warns" -Tag "NativeChecklist:switch-false" {
            $connectWarnings = @()
            @(Get-DbaDbMailHistory -SqlInstance "TCP:127.0.0.1,1" -EnableException:$false -WarningAction SilentlyContinue -WarningVariable connectWarnings).Count | Should -Be 0
            ($connectWarnings -join " ") | Should -BeLike "*Failure | *"
        }
    }

    Context "Failed read" {
        It "warns with the engine's message and writes no row" {
            $readWarnings = @()
            @(Get-DbaDbMailHistory -SqlInstance $lowServer -WarningAction SilentlyContinue -WarningVariable readWarnings).Count | Should -Be 0
            ($readWarnings -join " ") | Should -BeLike "*Query failure | An exception occurred while executing a Transact-SQL statement or batch.*SELECT permission was denied*"
        }

        It "goes on to the next instance after a failed read" -Tag "NativeChecklist:multi-instance-failure" {
            $readWarnings = @()
            $rows = @(Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $lowServer, $nativeServer -Status FAILED -WarningAction SilentlyContinue -WarningVariable readWarnings))
            $rows.Count | Should -Be 1
            @($readWarnings).Count | Should -Be 1
        }

        It "throws the Query method's fault under -EnableException, after the rows already written" -Tag "NativeChecklist:enable-exception" {
            $seen = New-Object System.Collections.ArrayList
            $thrown = $null
            try {
                Get-DbaDbMailHistory -SqlInstance $nativeServer, $lowServer -Status FAILED -EnableException | Where-Object Subject -like "$nativePrefix*" | ForEach-Object { $null = $seen.Add($PSItem) }
            } catch {
                $thrown = $PSItem
            }
            $seen.Count | Should -Be 1
            $thrown | Should -Not -BeNullOrEmpty
            $thrown.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMailHistory*"
            $thrown.CategoryInfo.Category.ToString() | Should -BeExactly "NotSpecified"
            $thrown.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $thrown.Exception.Message | Should -BeLike "An exception occurred while executing a Transact-SQL statement or batch.*SELECT permission was denied*"
            $thrown.Exception.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.MethodInvocationException"
            $thrown.Exception.InnerException.Message | Should -BeLike "Exception calling ""Query"" with ""1"" argument(s): *"
        }
    }

    Context "Mail whose profile was removed" {
        It "returns a mail whose profile was removed" {
            $rows = @(Get-NativeOwnRow -Rows (Get-DbaDbMailHistory -SqlInstance $nativeServer) | Where-Object Subject -eq "$($nativePrefix)profile removed")
            $rows.Count | Should -Be 1
            $rows[0].ProfileId | Should -Be $removedId
            $rows[0].Profile | Should -BeOfType [System.DBNull]
            $rows[0].SentStatus | Should -BeExactly "Sent"
        }

        It "returns one row per message of sysmail_allitems" {
            $recorded = $nativeServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM msdb.dbo.sysmail_allitems;")
            @(Get-DbaDbMailHistory -SqlInstance $nativeServer).Count | Should -Be $recorded
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        # Read-only: the SQL version lanes reach this one shared instance at the same moment, and a cleanup of mail rows written here failed a leg.
        It "works with -SqlCredential" {
            $credentialWarnings = @()
            $rows = @(Get-DbaDbMailHistory -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException -WarningAction SilentlyContinue -WarningVariable credentialWarnings)
            @($credentialWarnings).Count | Should -Be 0
            foreach ($row in $rows) {
                $row.SentStatus | Should -BeIn "Unsent", "Sent", "Failed", "Retrying"
            }
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            @(Get-DbaDbMailHistory -SqlInstance $loginInstance -WarningVariable loginWarnings -WarningAction SilentlyContinue).Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure | *Login failed for user*"
        }

        It "throws without the credential under -EnableException, as the pinned function does" {
            # The pinned catch around Connect-DbaInstance is a Stop-Function, which throws under -EnableException.
            $thrown = $null
            try {
                $null = Get-DbaDbMailHistory -SqlInstance $loginInstance -EnableException
            } catch {
                $thrown = $PSItem
            }
            $thrown | Should -Not -BeNullOrEmpty
            $thrown.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMailHistory*"
            $thrown.CategoryInfo.Category.ToString() | Should -BeExactly "ConnectionError"
        }
    }
}

Describe "Get-DbaDbMailHistory Azure refusal" -Tag IntegrationTests, NativeChecklist:azure-sqldb {
    It "refuses Azure SQL Database, which has no Database Mail" {
        # msdb and Database Mail are absent from Azure SQL Database:
        # https://learn.microsoft.com/azure/azure-sql/database/features-comparison#features-of-sql-database-and-sql-managed-instance
        $azureServer = $null
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureServer = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $errorDetail = $PSItem.Exception
                    $resuming = $false
                    while ($errorDetail) {
                        # The serverless database resumes, and the lab's mobile internet loses name resolution for a moment.
                        if ($errorDetail.Number -in 40613, -2 -or $errorDetail -is [System.TimeoutException] -or $errorDetail.Message -like "*No such host is known*") { $resuming = $true }
                        $errorDetail = $errorDetail.InnerException
                    }
                    if (-not $resuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureWarnings = @()
            @(Get-DbaDbMailHistory -SqlInstance $azureServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureWarnings).Count | Should -Be 0
            ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
            { Get-DbaDbMailHistory -SqlInstance $azureServer -EnableException } | Should -Throw "*Azure SQL Database not supported*"
        } finally {
            if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
        }
    }
}
