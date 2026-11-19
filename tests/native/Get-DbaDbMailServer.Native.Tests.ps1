#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbMailServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads Database Mail accounts.

Describe "Native Get-DbaDbMailServer" -Tag IntegrationTests {
    BeforeAll {
        # The legs of one SQL version share the instances and run one after the other; every name carries this run's number.
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $stamp = Get-Random
        $accountA = "dbatoolsci_nativems_${stamp}_a"
        $accountB = "dbatoolsci_nativems_${stamp}_b"
        $profileName = "dbatoolsci_nativems_${stamp}_p"
        $smtpA = "smtp-a-$stamp.dbatools.example"
        $smtpB = "smtp-b-$stamp.dbatools.example"
        $smtpPassword = "Nms-$([guid]::NewGuid().ToString('N'))"
        $null = $server.Query("EXEC msdb.dbo.sysmail_add_account_sp @account_name = N'$accountA', @email_address = N'a@dbatools.example', @mailserver_name = N'$smtpA', @port = 2525, @enable_ssl = 1, @username = N'nativeuser', @password = N'$smtpPassword';")
        $null = $server.Query("EXEC msdb.dbo.sysmail_add_account_sp @account_name = N'$accountB', @email_address = N'b@dbatools.example', @mailserver_name = N'$smtpB';")
        $null = $server.Query("EXEC msdb.dbo.sysmail_add_profile_sp @profile_name = N'$profileName';")
        $null = $server.Query("EXEC msdb.dbo.sysmail_add_profileaccount_sp @profile_name = N'$profileName', @account_name = N'$accountA', @sequence_number = 1;")

        $mail = Get-DbaDbMail -SqlInstance $instance -EnableException
        $mailTwo = Get-DbaDbMail -SqlInstance $instance -EnableException
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $bindingMessage = "Cannot bind argument to parameter 'SqlInstance' because it is null."

        # sqlwhale22 is shared: its account and logins are unique per leg and run.
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        $loginAccount = "dbatoolsci_nativems_${stamp}_l"
        $loginSmtp = "smtp-l-$stamp.dbatools.example"
        $noneName = "dbatoolsci_nmsn_$stamp"
        $partName = "dbatoolsci_nmsp_$stamp"
        $lowPassword = "Nms-$([guid]::NewGuid().ToString('N'))"
        $noneCred = New-Object System.Management.Automation.PSCredential -ArgumentList $noneName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $partCred = New-Object System.Management.Automation.PSCredential -ArgumentList $partName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $null = $loginServer.Query("EXEC msdb.dbo.sysmail_add_account_sp @account_name = N'$loginAccount', @email_address = N'l@dbatools.example', @mailserver_name = N'$loginSmtp';")
        $null = $loginServer.Query("CREATE LOGIN [$noneName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        $null = $loginServer.Query("CREATE LOGIN [$partName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        $null = $loginServer.Query("CREATE USER [$partName] FOR LOGIN [$partName]; GRANT EXECUTE ON dbo.sysmail_help_account_sp TO [$partName];", "msdb")
        $deniedAccounts = "The EXECUTE permission was denied on the object 'sysmail_help_account_sp', database 'msdb', schema 'dbo'."
        $deniedProfiles = "The SELECT permission was denied on the object 'sysmail_profileaccount', database 'msdb', schema 'dbo'."

        # The records one nested function's Stop-Function leaves in the caller's -ErrorVariable. The pin's nested Stop-Function
        # record reaches the caller's -ErrorVariable in every call mode on both editions (Get-DbaClientProtocol pin probes 236550ae
        # and 86cfbcd7; watchman 22dc72e0, correction nested-error-variable in WarnNestedStopFunction). Its id carries ",Stop-Function"
        # and the pin's list also holds the records of calls its nested function caught: the accepted differences
        # stop-record-id-stem-and-activity and omitted-consequential-records, so the id is matched by its stem.
        function Select-NativeNestedRecord {
            param($Records, [string]$FunctionName)
            $stem = "^dbatools_" + [regex]::Escape($FunctionName) + "(,|$)"
            @($Records | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] -and $PSItem.FullyQualifiedErrorId -match $stem })
        }

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments, [string]$Script = 'param($Arguments) Get-DbaDbMailServer @Arguments; "next statement"')
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaDbMailServer -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbMailServer", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript($Script).AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Output   = @($outsideOutput)
                    Errors   = @($outsideShell.Streams.Error)
                    Warnings = @($outsideShell.Streams.Warning)
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }
    }

    AfterAll {
        $null = $server.Query("IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile WHERE name = N'$profileName') EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = N'$profileName';")
        foreach ($account in $accountA, $accountB) {
            $null = $server.Query("IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_account WHERE name = N'$account') EXEC msdb.dbo.sysmail_delete_account_sp @account_name = N'$account';")
        }
        $null = $loginServer.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name IN (N'$noneName', N'$partName'); EXEC sys.sp_executesql @kill;")
        $null = $loginServer.Query("IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_account WHERE name = N'$loginAccount') EXEC msdb.dbo.sysmail_delete_account_sp @account_name = N'$loginAccount';")
        $null = $loginServer.Query("IF USER_ID(N'$partName') IS NOT NULL DROP USER [$partName];", "msdb")
        $null = $loginServer.Query("IF SUSER_ID(N'$noneName') IS NOT NULL DROP LOGIN [$noneName];")
        $null = $loginServer.Query("IF SUSER_ID(N'$partName') IS NOT NULL DROP LOGIN [$partName];")
    }

    Context "Output" {
        It "returns each mail server as the engine reports it, in account order" {
            $engine = @($server.Query("EXEC msdb.dbo.sysmail_help_account_sp;"))
            $result = @(Get-DbaDbMailServer -SqlInstance $instance -EnableException | Where-Object Name -in $smtpA, $smtpB)
            ($result.Name -join ",") | Should -BeExactly "$smtpA,$smtpB"
            foreach ($row in $result) {
                $source = $engine | Where-Object servername -eq $row.Name
                $row.Port | Should -Be $source.port
                $row.EnableSsl | Should -Be $source.enable_ssl
                $row.ServerType | Should -BeExactly ([string]$source.servertype)
                "$($row.UserName)" | Should -BeExactly "$($source.username)"
                $row.UseDefaultCredentials | Should -Be $source.use_default_credentials
            }
            $result[0].Port | Should -Be 2525
            $result[0].EnableSsl | Should -BeTrue
            $result[0].UserName | Should -BeExactly "nativeuser"
        }

        It "keeps the SMO type, the instance columns and the pinned default view" {
            $row = Get-DbaDbMailServer -SqlInstance $instance -Account $accountA -EnableException
            $row | Should -BeOfType Microsoft.SqlServer.Management.Smo.Mail.MailServer
            $row.ComputerName | Should -Be $server.ComputerName
            $row.InstanceName | Should -Be $server.ServiceName
            $row.SqlInstance | Should -Be $server.DomainInstanceName
            $row.Account | Should -BeExactly $accountA
            ($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
                Should -BeExactly "ComputerName,InstanceName,SqlInstance,Account,Name,Port,EnableSsl,ServerType,UserName,UseDefaultCredentials,NoCredentialChange"
        }

        It "leaves the columns and the view of Get-DbaDbMailAccount on the account behind each row" {
            $row = Get-DbaDbMailServer -SqlInstance $instance -Account $accountA -EnableException
            $row.Parent | Should -BeOfType Microsoft.SqlServer.Management.Smo.Mail.MailAccount
            $row.Parent.ComputerName | Should -Be $server.ComputerName
            $row.Parent.InstanceName | Should -Be $server.ServiceName
            $row.Parent.SqlInstance | Should -Be $server.DomainInstanceName
            $row.Parent.MailProfile | Should -BeExactly $profileName
            ($row.Parent.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
                Should -BeExactly "ComputerName,InstanceName,SqlInstance,ID,Name,DisplayName,Description,EmailAddress,ReplyToAddress,IsBusyAccount,MailServers,MailProfile"
            @((Get-DbaDbMailServer -SqlInstance $instance -Account $accountB -EnableException).Parent.MailProfile).Count | Should -Be 0
        }

        It "stops quietly when downstream takes only the first server" {
            foreach ($enableException in $false, $true) {
                $first = @(Get-DbaDbMailServer -SqlInstance $instance, $badInstance -Account $accountA, $accountB -EnableException:$enableException -WarningAction SilentlyContinue | Select-Object -First 1)
                $first.Count | Should -Be 1
            }
        }
    }

    Context "-Server" {
        It "matches a whole name without regard to case, and keeps the order of the accounts" {
            (Get-DbaDbMailServer -SqlInstance $instance -Server $smtpA.ToUpperInvariant() -EnableException).Name | Should -BeExactly $smtpA
            (@(Get-DbaDbMailServer -SqlInstance $instance -Server $smtpB, $smtpA -EnableException).Name -join ",") | Should -BeExactly "$smtpA,$smtpB"
            @(Get-DbaDbMailServer -SqlInstance $instance -Server $smtpA, $smtpA -EnableException).Count | Should -Be 1
        }

        It "gives nothing and no warning for a name no server has, as a pattern too" {
            foreach ($value in "no.such.server", "smtp-a-*") {
                $warnings = @()
                @(Get-DbaDbMailServer -SqlInstance $instance -Server $value -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
                $warnings.Count | Should -Be 0
            }
        }

        It "reads -Server by its truth, so a lone empty value filters nothing and two of them match nothing" {
            @(Get-DbaDbMailServer -SqlInstance $instance -Account $accountA -Server "" -EnableException).Count | Should -Be 1
            @(Get-DbaDbMailServer -SqlInstance $instance -Account $accountA -Server @() -EnableException).Count | Should -Be 1
            @(Get-DbaDbMailServer -SqlInstance $instance -Account $accountA -Server $null -EnableException).Count | Should -Be 1
            @(Get-DbaDbMailServer -SqlInstance $instance -Account $accountA -Server "", "" -EnableException).Count | Should -Be 0
        }

        It "gives nothing for a server of another account" {
            @(Get-DbaDbMailServer -SqlInstance $instance -Account $accountA -Server $smtpB -EnableException).Count | Should -Be 0
            (Get-DbaDbMailServer -SqlInstance $instance -Account $accountA, $accountB -Server $smtpB -EnableException).Name | Should -BeExactly $smtpB
        }

        It "takes the pinned alias and positions" {
            (Get-DbaDbMailServer -SqlInstance $instance -Name $smtpA -EnableException).Name | Should -BeExactly $smtpA
            (Get-DbaDbMailServer $instance $null $smtpA $accountA -EnableException).Name | Should -BeExactly $smtpA
            (Get-DbaDbMailServer $null $null $smtpA $null $mail -EnableException).Name | Should -BeExactly $smtpA
        }
    }

    Context "-Account" {
        It "matches a whole name without regard to case, and keeps the order of the accounts" {
            (Get-DbaDbMailServer -SqlInstance $instance -Account $accountA.ToUpperInvariant() -EnableException).Name | Should -BeExactly $smtpA
            (@(Get-DbaDbMailServer -SqlInstance $instance -Account $accountB, $accountA -EnableException).Name -join ",") | Should -BeExactly "$smtpA,$smtpB"
            @(Get-DbaDbMailServer -SqlInstance $instance -Account $accountA, $accountA -EnableException).Count | Should -Be 1
        }

        It "gives nothing and no warning for a name no account has, as a pattern too" {
            foreach ($value in "NoSuchAccount", "dbatoolsci_nativems_*") {
                $warnings = @()
                @(Get-DbaDbMailServer -SqlInstance $instance -Account $value -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
                $warnings.Count | Should -Be 0
            }
        }

        It "reads -Account by its truth, so a lone empty value filters nothing and two of them match nothing" {
            @(Get-DbaDbMailServer -SqlInstance $instance -Server $smtpA -Account "" -EnableException).Count | Should -Be 1
            @(Get-DbaDbMailServer -SqlInstance $instance -Server $smtpA -Account @() -EnableException).Count | Should -Be 1
            @(Get-DbaDbMailServer -SqlInstance $instance -Server $smtpA -Account $null -EnableException).Count | Should -Be 1
            @(Get-DbaDbMailServer -SqlInstance $instance -Account "", "" -EnableException).Count | Should -Be 0
        }
    }

    Context "No input" {
        It "warns that there are no servers, under -EnableException:`$false too" -Tag "NativeChecklist:switch-false" {
            $forms = @(
                @{ },
                @{ SqlInstance = $null },
                @{ SqlInstance = @() },
                @{ SqlInstance = @($null) },
                @{ InputObject = $null },
                @{ InputObject = @() },
                @{ InputObject = @($null) }
            )
            foreach ($form in $forms) {
                $warnings = @()
                @(Get-DbaDbMailServer @form -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match "\[Get-DbaDbMailServer\] No servers to process$"
            }
        }

        It "throws that under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaDbMailServer -EnableException
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly "No servers to process"
            $failure.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMailServer*"
            $failure.CategoryInfo.Category | Should -Be "NotSpecified"
            $failure.TargetObject | Should -BeNullOrEmpty
        }

        It "warns for each piped record that brings nothing, and still reads the next" {
            $warnings = @()
            @($null, $null | Get-DbaDbMailServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 2

            $warnings = @()
            $result = @($null, $mail | Get-DbaDbMailServer -Account $accountA -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $result.Name | Should -BeExactly $smtpA
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbMailServer\] No servers to process$"
        }
    }

    Context "Mail objects" {
        It "reads several mail objects, piped or named" -Tag "NativeChecklist:pipeline-multiple" {
            $piped = @($mail, $mailTwo | Get-DbaDbMailServer -Account $accountA -EnableException)
            $piped.Count | Should -Be 2
            [object]::ReferenceEquals($piped[0].Parent.Parent, $mail) | Should -BeTrue
            [object]::ReferenceEquals($piped[1].Parent.Parent, $mailTwo) | Should -BeTrue
            @(Get-DbaDbMailServer -InputObject $mail, $mailTwo -Account $accountA -EnableException).Count | Should -Be 2
            @($instance, $instance | Get-DbaDbMail -EnableException | Get-DbaDbMailServer -Account $accountA -EnableException).Count | Should -Be 2
        }

        It "puts the named instances after the input" {
            $result = @(Get-DbaDbMailServer -InputObject $mail -SqlInstance $server -Account $accountA -EnableException)
            $result.Count | Should -Be 2
            [object]::ReferenceEquals($result[0].Parent.Parent, $mail) | Should -BeTrue
            [object]::ReferenceEquals($result[1].Parent.Parent, $mail) | Should -BeFalse
        }

        It "refuses a value that is no mail object, by the pinned binding faults" {
            $failure = $null
            try {
                $null = Get-DbaDbMailServer -InputObject "notmail"
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentTransformationError,*"
            $failure.Exception.Message | Should -BeExactly "Cannot process argument transformation on parameter 'InputObject'. Cannot convert the `"notmail`" value of type `"System.String`" to type `"Microsoft.SqlServer.Management.Smo.Mail.SqlMail[]`"."

            $errors = @()
            @("notmail" | Get-DbaDbMailServer -ErrorAction SilentlyContinue -ErrorVariable errors).Count | Should -Be 0
            $errors.Count | Should -Be 1
            $errors[0].FullyQualifiedErrorId | Should -BeLike "InputObjectNotBound,*"
        }
    }

    Context "Failed instances" {
        It "warns as Get-DbaDbMail, then that there are no servers" {
            $warnings = @()
            $errors = @()
            @(Get-DbaDbMailServer -SqlInstance $badInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors).Count | Should -Be 0
            $warnings.Count | Should -Be 2
            "$($warnings[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| "
            "$($warnings[1])" | Should -Match "\[Get-DbaDbMailServer\] No servers to process$"
            # -ErrorVariable holds the nested Get-DbaDbMail's connection record, then this command's own.
            $errors.Count | Should -Be 2
            @(Select-NativeNestedRecord $errors[0] "Get-DbaDbMail").Count | Should -Be 1
            $errors[0].CategoryInfo.Category | Should -Be "ConnectionError"
            # The target is the instance as the message target transform gives it, its FullSmoName.
            "$($errors[0].TargetObject)" | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$badInstance).FullSmoName
            $errors[0].Exception.Message | Should -Not -BeNullOrEmpty
            "$($warnings[0])".EndsWith("Failure | " + $errors[0].Exception.Message) | Should -BeTrue
            @(Select-NativeNestedRecord $errors[1] "Get-DbaDbMailServer").Count | Should -Be 1
            $errors[1].Exception.Message | Should -BeExactly "No servers to process"
        }

        It "throws only the second under -EnableException, where the pinned call never carries that switch" -Tag "NativeChecklist:enable-exception" {
            $warnings = @()
            $errors = @()
            $failure = $null
            try {
                $null = Get-DbaDbMailServer -SqlInstance $badInstance -EnableException -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly "No servers to process"
            "$($warnings[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| "
            # The nested call never carries -EnableException, so its record still reaches -ErrorVariable.
            $nested = @(Select-NativeNestedRecord $errors "Get-DbaDbMail")
            $nested.Count | Should -Be 1
            $nested[0].CategoryInfo.Category | Should -Be "ConnectionError"
            "$($warnings[0])".EndsWith("Failure | " + $nested[0].Exception.Message) | Should -BeTrue
        }

        It "warns of a failed named instance and still reads the mail objects beside it, with no error" {
            $warnings = @()
            $errors = @()
            $merged = @(Get-DbaDbMailServer -InputObject $mail -SqlInstance $badInstance -Account $accountA -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors 2>&1)
            @($merged | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
            $merged.Name | Should -BeExactly $smtpA
            $warnings.Count | Should -Be 1
            # The nested record is not written to the error stream, but it reaches -ErrorVariable.
            $errors.Count | Should -Be 1
            @(Select-NativeNestedRecord $errors "Get-DbaDbMail").Count | Should -Be 1
        }

        It "warns of a failed instance among good ones and reads the others, -EnableException or not" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
            foreach ($enableException in $false, $true) {
                $warnings = @()
                $errors = @()
                $result = @(Get-DbaDbMailServer -SqlInstance $instance, $badInstance, $instance -Account $accountA -EnableException:$enableException -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
                $result.Count | Should -Be 2
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| "
                # -ErrorVariable holds the nested Get-DbaDbMail's record for the failed instance, and nothing of this command's own.
                $errors.Count | Should -Be 1
                @(Select-NativeNestedRecord $errors "Get-DbaDbMail").Count | Should -Be 1
                $errors[0].CategoryInfo.Category | Should -Be "ConnectionError"
                "$($errors[0].TargetObject)" | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$badInstance).FullSmoName
            }
        }
    }

    Context "Null elements" {
        It "outside any try, a plain call writes the binding fault of the nested Get-DbaDbMail, reads no instance of that array, warns that there are no servers and goes on" {
            foreach ($value in @(@($null, $instance), @($instance, $null), @($null, $null))) {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $value; Account = $accountA }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 1
                $outside.Errors[0].Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
                $outside.Errors[0].Exception.Message | Should -BeExactly $bindingMessage
                $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $outside.Errors[0].CategoryInfo.Category | Should -Be "InvalidData"
                $outside.Errors[0].CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $outside.Errors[0].CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMail"
                $outside.Errors[0].TargetObject | Should -BeNullOrEmpty
                $outside.Warnings.Count | Should -Be 1
                $outside.Warnings[0].Message | Should -Match "\[Get-DbaDbMailServer\] No servers to process$"
                ($outside.Output -join ",") | Should -BeExactly "next statement"
            }
        }

        It "outside any try, a plain call with a null -SqlInstance only warns that there are no servers, as the pin does" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $null; Account = $accountA }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 1
            $outside.Warnings[0].Message | Should -Match "\[Get-DbaDbMailServer\] No servers to process$"
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "outside any try, a plain call writes the fault and still reads the mail objects given beside the instances" {
            foreach ($value in @(@($null, $instance), @($instance, $null))) {
                $outside = Invoke-NativeOutsideTry @{ InputObject = $mail; SqlInstance = $value; Account = $accountA }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 1
                $outside.Errors[0].Exception.Message | Should -BeExactly $bindingMessage
                $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $outside.Errors[0].CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMail"
                $outside.Warnings.Count | Should -Be 0
                $outside.Output.Count | Should -Be 2
                $outside.Output[0].Name | Should -BeExactly $smtpA
                [object]::ReferenceEquals($outside.Output[0].Parent.Parent, $mail) | Should -BeTrue
                $outside.Output[1] | Should -BeExactly "next statement"
            }
        }

        It "inside a caller's try, the fault stops the command and the catch receives it, with no server and no warning out" {
            foreach ($form in @(@{ SqlInstance = @($null, $instance) }, @{ SqlInstance = @($instance, $null) }, @{ SqlInstance = @($null, $null) }, @{ SqlInstance = @($null, $instance); InputObject = $mail })) {
                $streamed = New-Object System.Collections.ArrayList
                $warnings = @()
                $failure = $null
                $after = $false
                try {
                    Get-DbaDbMailServer @form -Account $accountA -WarningAction SilentlyContinue -WarningVariable warnings | ForEach-Object { $null = $streamed.Add($PSItem) }
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                $failure | Should -Not -BeNullOrEmpty
                $failure.Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
                $failure.Exception.Message | Should -BeExactly $bindingMessage
                $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $failure.CategoryInfo.Category | Should -Be "InvalidData"
                $failure.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $failure.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMailServer"
                $failure.TargetObject | Should -BeNullOrEmpty
                $after | Should -BeFalse
                $streamed.Count | Should -Be 0
                $warnings.Count | Should -Be 0
            }
        }

        It "stops at the fault only under -EnableException, with no server out" -Tag "NativeChecklist:enable-exception" {
            foreach ($form in @(@{ SqlInstance = @($null, $instance) }, @{ SqlInstance = @($instance, $null) }, @{ SqlInstance = @($null, $instance); InputObject = $mail })) {
                $streamed = New-Object System.Collections.ArrayList
                $failure = $null
                try {
                    Get-DbaDbMailServer @form -Account $accountA -EnableException | ForEach-Object { $null = $streamed.Add($PSItem) }
                } catch {
                    $failure = $PSItem
                }
                $failure.Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
                $failure.Exception.Message | Should -BeExactly $bindingMessage
                $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $failure.CategoryInfo.Category | Should -Be "InvalidData"
                $failure.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $failure.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMailServer"
                $streamed.Count | Should -Be 0
            }
        }

        It "stops at the fault under -ErrorAction Stop, with no server out" {
            foreach ($form in @(@{ SqlInstance = @($null, $instance) }, @{ SqlInstance = @($instance, $null) }, @{ SqlInstance = @($null, $instance); InputObject = $mail })) {
                $streamed = New-Object System.Collections.ArrayList
                $failure = $null
                try {
                    Get-DbaDbMailServer @form -Account $accountA -ErrorAction Stop | ForEach-Object { $null = $streamed.Add($PSItem) }
                } catch {
                    $failure = $PSItem
                }
                $failure.Exception.Message | Should -BeExactly $bindingMessage
                $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $failure.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMailServer"
                $streamed.Count | Should -Be 0
            }
        }

        It "outside any try, -EnableException ends the command at the fault and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $mail; SqlInstance = @($null, $instance); Account = $accountA; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.Message | Should -BeExactly $bindingMessage
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
            $outside.Errors[0].CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMail"
            $outside.Warnings.Count | Should -Be 0
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "outside any try, -ErrorAction Stop turns the fault into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $mail; SqlInstance = @($null, $instance); Account = $accountA; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Stop.ErrorRecord.Exception.Message | Should -BeExactly $bindingMessage
            $outside.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
            $outside.Stop.ErrorRecord.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMailServer"
            $outside.Output.Count | Should -Be 0
        }

        # Accepted differences from the pin: harness-edits.md, "Script-scope preferences and the one-line connect warning", point 1.
        It "outside any try, Stop set in the caller's scope stops at the fault, as for any compiled command" {
            $script = 'param($Arguments) & { $ErrorActionPreference = "Stop"; Get-DbaDbMailServer @Arguments; "next statement" }; "after scope"'
            $outside = Invoke-NativeOutsideTry @{ InputObject = $mail; SqlInstance = @($null, $instance); Account = $accountA } -Script $script
            $outside.Stop | Should -Not -BeNullOrEmpty
            $outside.Stop.ErrorRecord.Exception.Message | Should -BeExactly $bindingMessage
            $outside.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
            $outside.Stop.ErrorRecord.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMail"
            $outside.Output.Count | Should -Be 0
        }

        It "outside any try, SilentlyContinue set in the caller's scope silences the fault and the command goes on" {
            $script = 'param($Arguments) & { $ErrorActionPreference = "SilentlyContinue"; Get-DbaDbMailServer @Arguments; "next statement" }; "after scope"'
            $outside = Invoke-NativeOutsideTry @{ InputObject = $mail; SqlInstance = @($null, $instance); Account = $accountA } -Script $script
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            $outside.Output.Count | Should -Be 3
            $outside.Output[0].Name | Should -BeExactly $smtpA
            $outside.Output[1] | Should -BeExactly "next statement"
            $outside.Output[2] | Should -BeExactly "after scope"
        }

        It "warns under Get-DbaDbMailAccount for a null mail object and reads the next, whatever -EnableException and -ErrorAction say" {
            foreach ($form in @(@{ }, @{ EnableException = $true }, @{ ErrorAction = "Stop" })) {
                $warnings = @()
                $errors = @()
                $result = @(Get-DbaDbMailServer -InputObject @($null, $mail) -Account $accountA @form -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
                $result.Name | Should -BeExactly $smtpA
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match "\[Get-DbaDbMailAccount\] No servers to process$"
                # The nested Get-DbaDbMailAccount's Stop-Function record reaches -ErrorVariable in each form.
                $errors.Count | Should -Be 1
                @(Select-NativeNestedRecord $errors "Get-DbaDbMailAccount").Count | Should -Be 1
                $errors[0].Exception.Message | Should -BeExactly "No servers to process"
                $errors[0].CategoryInfo.Category | Should -Be "NotSpecified"
                $errors[0].TargetObject | Should -BeNullOrEmpty

                $warnings = @()
                $errors = @()
                @(Get-DbaDbMailServer -InputObject @($null, $null) @form -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors).Count | Should -Be 0
                $warnings.Count | Should -Be 2
                $errors.Count | Should -Be 2
                @(Select-NativeNestedRecord $errors "Get-DbaDbMailAccount").Count | Should -Be 2
            }
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaDbMailServer -SqlInstance $loginInstance -SqlCredential $loginCred -Account $loginAccount -EnableException)
            $result.Name | Should -BeExactly $loginSmtp
            $result[0].SqlInstance | Should -Be $loginServer.DomainInstanceName
        }

        It "warns without the credential, as the nested Get-DbaDbMail does" {
            $warnings = @()
            $errors = @()
            @(Get-DbaDbMailServer -SqlInstance $loginInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors).Count | Should -Be 0
            $warnings.Count | Should -Be 2
            "$($warnings[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| Login failed"
            "$($warnings[1])" | Should -Match "\[Get-DbaDbMailServer\] No servers to process$"
            # -ErrorVariable holds the nested Get-DbaDbMail's connection record, then this command's own.
            $errors.Count | Should -Be 2
            @(Select-NativeNestedRecord $errors[0] "Get-DbaDbMail").Count | Should -Be 1
            $errors[0].CategoryInfo.Category | Should -Be "ConnectionError"
            $errors[0].Exception.Message | Should -Match "^Login failed"
            @(Select-NativeNestedRecord $errors[1] "Get-DbaDbMailServer").Count | Should -Be 1
        }

        It "throws only that there are no servers under -EnableException" {
            $failure = $null
            try {
                $null = Get-DbaDbMailServer -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly "No servers to process"
        }
    }

    Context "A failed read" {
        It "warns under Get-DbaDbMailAccount of a login that cannot read the accounts, -EnableException or not, with or without a filter" {
            foreach ($form in @{ }, @{ Account = $loginAccount }, @{ Server = $loginSmtp }) {
                foreach ($enableException in $false, $true) {
                    $warnings = @()
                    $errors = @()
                    @(Get-DbaDbMailServer -SqlInstance $loginInstance -SqlCredential $noneCred @form -EnableException:$enableException -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors).Count | Should -Be 0
                    $warnings.Count | Should -Be 1
                    "$($warnings[0])" | Should -Match ("\[Get-DbaDbMailAccount\] Failure \| " + [regex]::Escape($deniedAccounts) + "$")
                    # The nested Get-DbaDbMailAccount's read record reaches -ErrorVariable, -EnableException or not.
                    $errors.Count | Should -Be 1
                    @(Select-NativeNestedRecord $errors "Get-DbaDbMailAccount").Count | Should -Be 1
                    $errors[0].Exception.Message | Should -BeExactly $deniedAccounts
                    $errors[0].CategoryInfo.Category | Should -Be "NotSpecified"
                    $errors[0].TargetObject | Should -BeNullOrEmpty
                }
            }
        }

        It "warns the same of a login that reads the accounts but not their profiles, and gives no server" {
            foreach ($enableException in $false, $true) {
                $warnings = @()
                $errors = @()
                @(Get-DbaDbMailServer -SqlInstance $loginInstance -SqlCredential $partCred -EnableException:$enableException -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors).Count | Should -Be 0
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match ("\[Get-DbaDbMailAccount\] Failure \| " + [regex]::Escape($deniedProfiles) + "$")
                $errors.Count | Should -Be 1
                @(Select-NativeNestedRecord $errors "Get-DbaDbMailAccount").Count | Should -Be 1
                $errors[0].Exception.Message | Should -BeExactly $deniedProfiles
            }
        }

        It "goes on to the next mail object, under -EnableException and -ErrorAction Stop too" -Tag "NativeChecklist:multi-instance-failure" {
            $lowMail = Get-DbaDbMail -SqlInstance $loginInstance -SqlCredential $noneCred -EnableException
            foreach ($form in @(@{ }, @{ EnableException = $true }, @{ ErrorAction = "Stop" })) {
                $warnings = @()
                $errors = @()
                $result = @($lowMail, $mail | Get-DbaDbMailServer -Account $accountA @form -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
                $result.Name | Should -BeExactly $smtpA
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match "\[Get-DbaDbMailAccount\] Failure \| "
                $errors.Count | Should -Be 1
                @(Select-NativeNestedRecord $errors "Get-DbaDbMailAccount").Count | Should -Be 1
                $errors[0].Exception.Message | Should -BeExactly $deniedAccounts
            }
        }
    }

    Context "Corrections" {
        It "reports the instance columns of a mail object read straight from a server" {
            $raw = (Connect-DbaInstance -SqlInstance $instance -EnableException).Mail
            foreach ($row in @($raw | Get-DbaDbMailServer -Account $accountA -EnableException), @(Get-DbaDbMailServer -InputObject $raw -Account $accountA -EnableException)) {
                $row.ComputerName | Should -Be $server.ComputerName
                $row.InstanceName | Should -Be $server.ServiceName
                $row.SqlInstance | Should -Be $server.DomainInstanceName
            }
        }

        It "reads a named instance once beside piped mail objects" {
            $warnings = @()
            $beside = @($mail, $mailTwo | Get-DbaDbMailServer -SqlInstance $instance -Account $accountA -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $beside.Count | Should -Be 3
            $warnings.Count | Should -Be 0

            $warnings = @()
            $afterNulls = @($null, $null | Get-DbaDbMailServer -SqlInstance $instance -Account $accountA -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $afterNulls.Count | Should -Be 1
            $warnings.Count | Should -Be 0
        }

        It "names each server's own account" {
            foreach ($form in @(@{ Account = @($accountA, $accountB) }, @{ Server = @($smtpA, $smtpB) })) {
                $result = @(Get-DbaDbMailServer -SqlInstance $instance @form -EnableException)
                $result.Count | Should -Be 2
                $result[0].Account | Should -BeExactly $accountA
                $result[1].Account | Should -BeExactly $accountB
                @($result | Where-Object Account -eq $accountA).Name | Should -BeExactly $smtpA
            }
        }
    }
}

Describe "Native Get-DbaDbMailServer on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 or times out (-2) while it resumes, and the lab's mobile
                # internet can drop a name lookup (11001, "No such host is known").
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 11001) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) {
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    # Database Mail is unavailable on Azure SQL Database: https://learn.microsoft.com/sql/relational-databases/database-mail/database-mail
    It "refuses Azure SQL Database as Get-DbaDbMail does, then reports no servers" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = @()
        $errors = @()
        @(Get-DbaDbMailServer -SqlInstance $azureServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors).Count | Should -Be 0
        $warnings.Count | Should -Be 2
        "$($warnings[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| .*Azure SQL Database not supported"
        "$($warnings[1])" | Should -Match "\[Get-DbaDbMailServer\] No servers to process$"
        # The nested Get-DbaDbMail's refusal record reaches -ErrorVariable, then this command's own (watchman 22dc72e0).
        $errors.Count | Should -Be 2
        $errors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaDbMail(,|$)"
        $errors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        $errors[0].Exception.Message | Should -Match "Azure SQL Database not supported"
        $errors[1].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaDbMailServer(,|$)"
        { Get-DbaDbMailServer -SqlInstance $azureServer -EnableException -WarningAction SilentlyContinue } | Should -Throw "No servers to process"
    }
}
