#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbMailProfile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads Database Mail profiles.

BeforeAll {
    # The pinned -WarningVariable also keeps the hidden line of the nested Connect-DbaInstance; what a caller sees is the rest.
    function Get-ShownWarning {
        param($Records)
        @($Records | Where-Object { "$PSItem" -notmatch "\[Connect-DbaInstance\]" })
    }
}

Describe "Native Get-DbaDbMailProfile" -Tag IntegrationTests {
    BeforeAll {
        # The legs of one SQL version share the instance and run one after the other; every name carries this run's number.
        $instance = $TestConfig.InstanceMulti1
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $stamp = Get-Random
        $nameA = "dbatoolsci_NativeMP_${stamp}_a"
        $nameB = "dbatoolsci_NativeMP_${stamp}_b"
        $nameC = "dbatoolsci_NativeMP_${stamp}_c"
        $accountOne = "dbatoolsci_nativemp_${stamp}_z"
        $accountTwo = "dbatoolsci_nativemp_${stamp}_y"
        foreach ($account in $accountOne, $accountTwo) {
            $null = $server.Query("EXEC msdb.dbo.sysmail_add_account_sp @account_name = N'$account', @email_address = N'$account@dbatools.example', @mailserver_name = N'smtp.dbatools.example';")
        }
        $null = $server.Query("EXEC msdb.dbo.sysmail_add_profile_sp @profile_name = N'$nameA', @description = N'Native profile a';")
        $null = $server.Query("EXEC msdb.dbo.sysmail_add_profile_sp @profile_name = N'$nameB';")
        $null = $server.Query("EXEC msdb.dbo.sysmail_add_profile_sp @profile_name = N'$nameC', @description = N'Native profile c';")
        $null = $server.Query("EXEC msdb.dbo.sysmail_add_profileaccount_sp @profile_name = N'$nameA', @account_name = N'$accountOne', @sequence_number = 1;")
        $null = $server.Query("EXEC msdb.dbo.sysmail_add_profileaccount_sp @profile_name = N'$nameA', @account_name = N'$accountTwo', @sequence_number = 2;")
        $null = $server.Query("EXEC msdb.dbo.sysmail_add_profileaccount_sp @profile_name = N'$nameB', @account_name = N'$accountOne', @sequence_number = 1;")

        $mail = Get-DbaDbMail -SqlInstance $instance -EnableException
        $mailTwo = Get-DbaDbMail -SqlInstance $instance -EnableException
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $engineProfiles = @($server.Query("EXEC msdb.dbo.sysmail_help_profile_sp;"))
        $bindingMessage = "Cannot bind argument to parameter 'SqlInstance' because it is null."

        # The cmdlet entry in a runspace of its own, so no try is above the call: the plain-call flow the pin has there.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments, [string]$Script = 'param($Arguments) Get-DbaDbMailProfile @Arguments; "next statement"')
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaDbMailProfile -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbMailProfile", $outsideType, $null
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
        foreach ($name in $nameA, $nameB, $nameC) {
            $null = $server.Query("IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile WHERE name = N'$name') EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = N'$name';")
        }
        foreach ($account in $accountOne, $accountTwo) {
            $null = $server.Query("IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_account WHERE name = N'$account') EXEC msdb.dbo.sysmail_delete_account_sp @account_name = N'$account';")
        }
    }

    Context "Output" {
        It "returns every profile as the engine reports it" {
            $result = @(Get-DbaDbMailProfile -SqlInstance $instance -EnableException)
            $result.Count | Should -Be $engineProfiles.Count
            foreach ($row in $result) {
                $engineRow = $engineProfiles | Where-Object name -eq $row.Name
                $row.ID | Should -Be $engineRow.profile_id
                $row.Description | Should -BeExactly ([string]$engineRow.description)
            }
        }

        It "keeps the SMO type, the instance columns and the pinned default view" {
            foreach ($row in @(Get-DbaDbMailProfile -SqlInstance $instance -EnableException)) {
                $row | Should -BeOfType Microsoft.SqlServer.Management.Smo.Mail.MailProfile
                $row.ComputerName | Should -Be $server.ComputerName
                $row.InstanceName | Should -Be $server.ServiceName
                $row.SqlInstance | Should -Be $server.DomainInstanceName
                ($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
                    Should -BeExactly "ComputerName,InstanceName,SqlInstance,ID,Name,Description,ForceDeleteForActiveProfiles,IsBusyProfile,MailAccount"
            }
        }

        It "gives no account, the bare name of one, and an array of several, as the read returns them" {
            $two = Get-DbaDbMailProfile -SqlInstance $instance -Profile $nameA -EnableException
            $two.MailAccount.GetType().FullName | Should -BeExactly "System.Object[]"
            # The engine's procedure has no ORDER BY, and the two accounts came back in either order across the SQL versions.
            ($two.MailAccount -join ",") | Should -BeExactly (@($two.EnumAccounts().Rows | ForEach-Object AccountName) -join ",")
            ((@($two.MailAccount) | Sort-Object) -join ",") | Should -BeExactly "$accountTwo,$accountOne"

            $one = Get-DbaDbMailProfile -SqlInstance $instance -Profile $nameB -EnableException
            $one.MailAccount.GetType().FullName | Should -BeExactly "System.String"
            $one.MailAccount | Should -BeExactly $accountOne

            $none = Get-DbaDbMailProfile -SqlInstance $instance -Profile $nameC -EnableException
            $none.MailAccount | Should -BeNullOrEmpty
            $none.PSObject.Properties["MailAccount"].MemberType | Should -Be "NoteProperty"
        }

        It "stops quietly when downstream takes only the first profile" {
            foreach ($enableException in $false, $true) {
                $first = @(Get-DbaDbMailProfile -SqlInstance $instance, $badInstance -EnableException:$enableException -WarningAction SilentlyContinue | Select-Object -First 1)
                $first.Count | Should -Be 1
            }
        }
    }

    Context "-Profile" {
        It "matches a whole name without regard to case, and keeps the order of the collection" {
            (Get-DbaDbMailProfile -SqlInstance $instance -Profile $nameA.ToUpperInvariant() -EnableException).Name | Should -BeExactly $nameA
            (@(Get-DbaDbMailProfile -SqlInstance $instance -Profile $nameB, $nameA -EnableException).Name -join ",") | Should -BeExactly "$nameA,$nameB"
            @(Get-DbaDbMailProfile -SqlInstance $instance -Profile $nameA, $nameA -EnableException).Count | Should -Be 1
        }

        It "gives nothing and no warning for a name no profile has, as a pattern too" {
            foreach ($value in "NoSuchProfile", "dbatoolsci_NativeMP_*") {
                $warnings = @()
                @(Get-DbaDbMailProfile -SqlInstance $instance -Profile $value -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
                $warnings.Count | Should -Be 0
            }
        }

        It "reads -Profile by its truth, so a lone empty value filters nothing and two of them match nothing" {
            $all = $engineProfiles.Count
            @(Get-DbaDbMailProfile -SqlInstance $instance -Profile "" -EnableException).Count | Should -Be $all
            @(Get-DbaDbMailProfile -SqlInstance $instance -Profile @() -EnableException).Count | Should -Be $all
            @(Get-DbaDbMailProfile -SqlInstance $instance -Profile $null -EnableException).Count | Should -Be $all
            @(Get-DbaDbMailProfile -SqlInstance $instance -Profile "", "" -EnableException).Count | Should -Be 0
        }

        It "takes the pinned positions" {
            (Get-DbaDbMailProfile $instance $null $nameA -EnableException).Name | Should -BeExactly $nameA
            (Get-DbaDbMailProfile $null $null $nameA $null $mail -EnableException).Name | Should -BeExactly $nameA
        }
    }

    Context "-ExcludeProfile" {
        It "removes whole names without regard to case" {
            $names = @(Get-DbaDbMailProfile -SqlInstance $instance -ExcludeProfile $nameA.ToUpperInvariant(), $nameB -EnableException).Name
            $names | Should -Not -Contain $nameA
            $names | Should -Not -Contain $nameB
            $names | Should -Contain $nameC
        }

        It "removes nothing for a pattern" {
            @(Get-DbaDbMailProfile -SqlInstance $instance -ExcludeProfile "dbatoolsci_NativeMP_*" -EnableException).Count | Should -Be $engineProfiles.Count
        }

        It "reads -ExcludeProfile by its truth" {
            $all = $engineProfiles.Count
            foreach ($value in @("", @(), $null, @("", ""))) {
                @(Get-DbaDbMailProfile -SqlInstance $instance -ExcludeProfile $value -EnableException).Count | Should -Be $all
            }
        }

        It "applies after -Profile" {
            (Get-DbaDbMailProfile -SqlInstance $instance -Profile $nameA, $nameB -ExcludeProfile $nameA -EnableException).Name | Should -BeExactly $nameB
            (Get-DbaDbMailProfile $instance $null $nameA, $nameB $nameA -EnableException).Name | Should -BeExactly $nameB
        }
    }

    Context "No input" {
        It "warns that there are no servers, under -EnableException:`$false too" -Tag "NativeChecklist:switch-false" {
            $forms = @(
                @{ },
                @{ SqlInstance = $null },
                @{ SqlInstance = @() },
                @{ InputObject = $null },
                @{ InputObject = @() },
                @{ InputObject = @($null) }
            )
            foreach ($form in $forms) {
                $warnings = @()
                @(Get-DbaDbMailProfile @form -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match "\[Get-DbaDbMailProfile\] No servers to process$"
            }
            $warnings = @()
            @(Get-DbaDbMailProfile -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 1
        }

        It "throws that under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaDbMailProfile -EnableException
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly "No servers to process"
            $failure.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMailProfile*"
            $failure.CategoryInfo.Category | Should -Be "NotSpecified"
            $failure.TargetObject | Should -BeNullOrEmpty
        }

        It "warns for each piped record that brings nothing, and still reads the next" {
            $warnings = @()
            @($null, $null | Get-DbaDbMailProfile -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 2

            $warnings = @()
            $result = @($null, $mail | Get-DbaDbMailProfile -Profile $nameA -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $result.Name | Should -BeExactly $nameA
            $warnings.Count | Should -Be 1
        }

        It "passes null mail objects in silence, filtered or not" {
            foreach ($form in @{ }, @{ Profile = $nameA }, @{ ExcludeProfile = $nameA }) {
                $warnings = @()
                $errors = @()
                @(Get-DbaDbMailProfile -InputObject @($null, $null) @form -EnableException -WarningAction SilentlyContinue -WarningVariable warnings -ErrorAction SilentlyContinue -ErrorVariable errors).Count | Should -Be 0
                $warnings.Count | Should -Be 0
                $errors.Count | Should -Be 0
            }
            (Get-DbaDbMailProfile -InputObject @($null, $mail) -Profile $nameA -EnableException).Name | Should -BeExactly $nameA
            @(Get-DbaDbMailProfile -InputObject @($mail, $null) -ExcludeProfile $nameA -EnableException).Name | Should -Contain $nameB
        }
    }

    Context "Mail objects" {
        It "reads several mail objects, piped or named" -Tag "NativeChecklist:pipeline-multiple" {
            $piped = @($mail, $mailTwo | Get-DbaDbMailProfile -Profile $nameA -EnableException)
            $piped.Count | Should -Be 2
            [object]::ReferenceEquals($piped[0].Parent, $mail) | Should -BeTrue
            [object]::ReferenceEquals($piped[1].Parent, $mailTwo) | Should -BeTrue
            @(Get-DbaDbMailProfile -InputObject $mail, $mailTwo -Profile $nameA -EnableException).Count | Should -Be 2
            @($instance, $instance | Get-DbaDbMail -EnableException | Get-DbaDbMailProfile -Profile $nameA -EnableException).Count | Should -Be 2
        }

        It "puts the named instances after the input" {
            $result = @(Get-DbaDbMailProfile -InputObject $mail -SqlInstance $server -Profile $nameA -EnableException)
            $result.Count | Should -Be 2
            [object]::ReferenceEquals($result[0].Parent, $mail) | Should -BeTrue
            [object]::ReferenceEquals($result[1].Parent, $mail) | Should -BeFalse
        }

        It "refuses a value that is no mail object, by the pinned binding faults" {
            $failure = $null
            try {
                $null = Get-DbaDbMailProfile -InputObject "notmail"
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentTransformationError,*"
            $failure.Exception.Message | Should -BeExactly "Cannot process argument transformation on parameter 'InputObject'. Cannot convert the `"notmail`" value of type `"System.String`" to type `"Microsoft.SqlServer.Management.Smo.Mail.SqlMail[]`"."

            $errors = @()
            @("notmail" | Get-DbaDbMailProfile -ErrorAction SilentlyContinue -ErrorVariable errors).Count | Should -Be 0
            $errors.Count | Should -Be 1
            $errors[0].FullyQualifiedErrorId | Should -BeLike "InputObjectNotBound,*"
        }
    }

    Context "Failed instances" {
        It "warns as Get-DbaDbMail, then that there are no servers" {
            $warnings = @()
            @(Get-DbaDbMailProfile -SqlInstance $badInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $shown = @(Get-ShownWarning $warnings)
            $shown.Count | Should -Be 2
            "$($shown[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| "
            "$($shown[1])" | Should -Match "\[Get-DbaDbMailProfile\] No servers to process$"
        }

        It "throws only the second under -EnableException, where the pinned call never carries that switch" -Tag "NativeChecklist:enable-exception" {
            $warnings = @()
            $failure = $null
            try {
                $null = Get-DbaDbMailProfile -SqlInstance $badInstance -EnableException -WarningAction SilentlyContinue -WarningVariable warnings
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly "No servers to process"
            "$(@(Get-ShownWarning $warnings)[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| "
        }

        It "warns of a failed named instance and still reads the mail objects beside it, with no error" {
            $warnings = @()
            $merged = @(Get-DbaDbMailProfile -InputObject $mail -SqlInstance $badInstance -Profile $nameA -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings 2>&1)
            @($merged | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
            $merged.Count | Should -Be 1
            @(Get-ShownWarning $warnings).Count | Should -Be 1
        }

        It "warns of a failed instance among good ones and reads the others, -EnableException or not" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
            foreach ($enableException in $false, $true) {
                $warnings = @()
                $result = @(Get-DbaDbMailProfile -SqlInstance $instance, $badInstance, $instance -Profile $nameA -EnableException:$enableException -WarningAction SilentlyContinue -WarningVariable warnings)
                $result.Count | Should -Be 2
                $shown = @(Get-ShownWarning $warnings)
                $shown.Count | Should -Be 1
                "$($shown[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| "
            }
        }
    }

    Context "Null elements" {
        # The pin's own numbers for these forms, both editions: evidence/pin-mailprofile-20261101.txt (probe 00e65685) and
        # evidence/probe-run-pin-mailprofile-binder-route-20261117.txt (probe ee3db0cd). Pester runs each It inside a try, so the
        # plain-call forms run in a runspace of their own, outside any try.
        It "outside any try, a plain call writes one binding fault per null element and still reads the instances beside it" {
            $forms = @(
                @{ Value = @($null, $instance); Rows = 1 },
                @{ Value = @($instance, $null); Rows = 1 },
                @{ Value = @($instance, $null, $instance); Rows = 2 }
            )
            foreach ($form in $forms) {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $form.Value; Profile = $nameA }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 1
                $outside.Errors[0].Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
                $outside.Errors[0].Exception.Message | Should -BeExactly $bindingMessage
                $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $outside.Errors[0].CategoryInfo.Category | Should -Be "InvalidData"
                $outside.Errors[0].CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $outside.Errors[0].CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMail"
                $outside.Errors[0].TargetObject | Should -BeNullOrEmpty
                @(Get-ShownWarning $outside.Warnings).Count | Should -Be 0
                $outside.Output.Count | Should -Be ($form.Rows + 1)
                @($outside.Output | Select-Object -First $form.Rows | ForEach-Object { $PSItem.Name } | Sort-Object -Unique) -join "," | Should -BeExactly $nameA
                $outside.Output[-1] | Should -BeExactly "next statement"
            }
        }

        It "outside any try, a plain call reports each null element of an array of nulls, then that there are no servers" {
            foreach ($form in @(@{ Value = @($null, $null); Faults = 2 }, @{ Value = @($null); Faults = 1 })) {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $form.Value }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be $form.Faults
                @($outside.Errors | Where-Object { $PSItem.Exception.Message -ceq $bindingMessage -and $PSItem.CategoryInfo.Activity -ceq "Get-DbaDbMail" }).Count | Should -Be $form.Faults
                $shown = @(Get-ShownWarning $outside.Warnings)
                $shown.Count | Should -Be 1
                $shown[0].Message | Should -Match "\[Get-DbaDbMailProfile\] No servers to process$"
                ($outside.Output -join ",") | Should -BeExactly "next statement"
            }
        }

        It "outside any try, a plain call with a null or empty -SqlInstance only warns that there are no servers, as the pin's empty loop" {
            foreach ($form in @(@{ SqlInstance = $null }, @{ SqlInstance = @() })) {
                $outside = Invoke-NativeOutsideTry $form
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 0
                $shown = @(Get-ShownWarning $outside.Warnings)
                $shown.Count | Should -Be 1
                $shown[0].Message | Should -Match "\[Get-DbaDbMailProfile\] No servers to process$"
                ($outside.Output -join ",") | Should -BeExactly "next statement"
            }
        }

        It "outside any try, a plain call writes the fault and still reads the mail objects given beside the instances" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $mail; SqlInstance = @($instance, $null); Profile = $nameA }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.Message | Should -BeExactly $bindingMessage
            $outside.Errors[0].CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMail"
            $outside.Output.Count | Should -Be 3
            $outside.Output[0].Name | Should -BeExactly $nameA
            $outside.Output[1].Name | Should -BeExactly $nameA
            $outside.Output[2] | Should -BeExactly "next statement"
        }

        It "inside a caller's try, the fault stops the command and the catch receives it, with no row and no warning out" {
            foreach ($form in @(@{ SqlInstance = @($null, $instance) }, @{ SqlInstance = @($instance, $null) }, @{ SqlInstance = @($null, $null) }, @{ SqlInstance = @($instance, $null); InputObject = $mail })) {
                $streamed = New-Object System.Collections.ArrayList
                $warnings = @()
                $failure = $null
                $after = $false
                try {
                    Get-DbaDbMailProfile @form -Profile $nameA -WarningAction SilentlyContinue -WarningVariable warnings | ForEach-Object { $null = $streamed.Add($PSItem) }
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
                $failure.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMailProfile"
                $failure.TargetObject | Should -BeNullOrEmpty
                $after | Should -BeFalse
                $streamed.Count | Should -Be 0
                @(Get-ShownWarning $warnings).Count | Should -Be 0
            }
        }

        It "stops at the fault under -EnableException, with no row out" -Tag "NativeChecklist:enable-exception" {
            foreach ($form in @(@{ SqlInstance = @($null, $instance) }, @{ SqlInstance = @($instance, $null) }, @{ SqlInstance = @($instance, $null); InputObject = $mail })) {
                $streamed = New-Object System.Collections.ArrayList
                $failure = $null
                try {
                    Get-DbaDbMailProfile @form -Profile $nameA -EnableException | ForEach-Object { $null = $streamed.Add($PSItem) }
                } catch {
                    $failure = $PSItem
                }
                $failure.Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
                $failure.Exception.Message | Should -BeExactly $bindingMessage
                $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $failure.CategoryInfo.Category | Should -Be "InvalidData"
                $failure.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $failure.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMailProfile"
                $streamed.Count | Should -Be 0
            }
        }

        It "stops at the fault under -ErrorAction Stop, with no row out" {
            foreach ($form in @(@{ SqlInstance = @($null, $instance) }, @{ SqlInstance = @($instance, $null) }, @{ SqlInstance = @($instance, $null); InputObject = $mail })) {
                $streamed = New-Object System.Collections.ArrayList
                $failure = $null
                try {
                    Get-DbaDbMailProfile @form -Profile $nameA -ErrorAction Stop | ForEach-Object { $null = $streamed.Add($PSItem) }
                } catch {
                    $failure = $PSItem
                }
                $failure.Exception.Message | Should -BeExactly $bindingMessage
                $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $failure.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMailProfile"
                $streamed.Count | Should -Be 0
            }
        }

        It "outside any try, -EnableException ends the command at the fault and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $mail; SqlInstance = @($null, $instance); Profile = $nameA; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.Message | Should -BeExactly $bindingMessage
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
            $outside.Errors[0].CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMail"
            @(Get-ShownWarning $outside.Warnings).Count | Should -Be 0
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "outside any try, -ErrorAction Stop turns the fault into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $mail; SqlInstance = @($null, $instance); Profile = $nameA; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Stop.ErrorRecord.Exception.Message | Should -BeExactly $bindingMessage
            $outside.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
            $outside.Stop.ErrorRecord.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMailProfile"
            $outside.Output.Count | Should -Be 0
        }
    }

    Context "Corrections" {
        It "reports the instance columns of a mail object read straight from a server" {
            $raw = (Connect-DbaInstance -SqlInstance $instance -EnableException).Mail
            foreach ($row in @($raw | Get-DbaDbMailProfile -Profile $nameA -EnableException), @(Get-DbaDbMailProfile -InputObject $raw -Profile $nameA -EnableException)) {
                $row.ComputerName | Should -Be $server.ComputerName
                $row.InstanceName | Should -Be $server.ServiceName
                $row.SqlInstance | Should -Be $server.DomainInstanceName
            }
        }

        It "reads a named instance once beside piped mail objects" {
            $warnings = @()
            $beside = @($mail, $mailTwo | Get-DbaDbMailProfile -SqlInstance $instance -Profile $nameA -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $beside.Count | Should -Be 3
            $warnings.Count | Should -Be 0

            $warnings = @()
            $afterNulls = @($null, $null | Get-DbaDbMailProfile -SqlInstance $instance -Profile $nameA -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $afterNulls.Count | Should -Be 1
            $warnings.Count | Should -Be 0
        }
    }
}

Describe "Native Get-DbaDbMailProfile over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        # sqlwhale22 is shared: every name is unique per leg and run, and the fixture is removed at the end.
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        $stamp = Get-Random
        $loginProfile = "dbatoolsci_NativeMP_${stamp}_l"
        $loginAccount = "dbatoolsci_nativemp_${stamp}_x"
        $lowName = "dbatoolsci_nmp_$stamp"
        $lowPassword = "Nmp-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        $null = $loginServer.Query("EXEC msdb.dbo.sysmail_add_profile_sp @profile_name = N'$loginProfile', @description = N'Native login profile';")
        $null = $loginServer.Query("EXEC msdb.dbo.sysmail_add_account_sp @account_name = N'$loginAccount', @email_address = N'$loginAccount@dbatools.example', @mailserver_name = N'smtp.dbatools.example';")
        $null = $loginServer.Query("EXEC msdb.dbo.sysmail_add_profileaccount_sp @profile_name = N'$loginProfile', @account_name = N'$loginAccount', @sequence_number = 1;")
        $deniedMessage = "The EXECUTE permission was denied on the object 'sysmail_help_profile_sp', database 'msdb', schema 'dbo'."
    }

    AfterAll {
        $null = $loginServer.Query("IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile WHERE name = N'$loginProfile') EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = N'$loginProfile';")
        $null = $loginServer.Query("IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_account WHERE name = N'$loginAccount') EXEC msdb.dbo.sysmail_delete_account_sp @account_name = N'$loginAccount';")
        $null = $loginServer.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$lowName'; EXEC sys.sp_executesql @kill;")
        $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = Get-DbaDbMailProfile -SqlInstance $loginInstance -SqlCredential $loginCred -Profile $loginProfile -EnableException
            $result.Name | Should -BeExactly $loginProfile
            $result.MailAccount | Should -BeExactly $loginAccount
            $result.SqlInstance | Should -Be $loginServer.DomainInstanceName
        }

        It "warns without the credential, as the nested Get-DbaDbMail does" {
            $warnings = @()
            @(Get-DbaDbMailProfile -SqlInstance $loginInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $shown = @(Get-ShownWarning $warnings)
            $shown.Count | Should -Be 2
            "$($shown[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| Login failed"
            "$($shown[1])" | Should -Match "\[Get-DbaDbMailProfile\] No servers to process$"
        }

        It "throws only that there are no servers under -EnableException" {
            $failure = $null
            try {
                $null = Get-DbaDbMailProfile -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly "No servers to process"
        }
    }

    Context "A failed read" {
        It "warns of a login that cannot read the profiles, filtered or not" {
            foreach ($form in @{ }, @{ Profile = $loginProfile }, @{ ExcludeProfile = $loginProfile }) {
                $warnings = @()
                @(Get-DbaDbMailProfile -SqlInstance $loginInstance -SqlCredential $lowCred @form -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match ("\[Get-DbaDbMailProfile\] Failure \| " + [regex]::Escape($deniedMessage) + "$")
            }
        }

        It "throws the pinned record under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaDbMailProfile -SqlInstance $loginInstance -SqlCredential $lowCred -EnableException
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $failure.Exception.Message | Should -BeExactly $deniedMessage
            $failure.Exception.InnerException.GetType().FullName | Should -BeExactly "Microsoft.Data.SqlClient.SqlException"
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMailProfile*"
            $failure.CategoryInfo.Category | Should -Be "NotSpecified"
            $failure.TargetObject | Should -BeNullOrEmpty
        }

        It "goes on to the next mail object, and stops there under -EnableException" -Tag "NativeChecklist:multi-instance-failure" {
            $lowMail = Get-DbaDbMail -SqlInstance $loginInstance -SqlCredential $lowCred -EnableException
            $goodMail = Get-DbaDbMail -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $warnings = @()
            $result = @($lowMail, $goodMail | Get-DbaDbMailProfile -Profile $loginProfile -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $result.Name | Should -BeExactly $loginProfile
            $warnings.Count | Should -Be 1

            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            try {
                $lowMail, $goodMail | Get-DbaDbMailProfile -Profile $loginProfile -EnableException | ForEach-Object { $null = $streamed.Add($PSItem) }
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly $deniedMessage
            $streamed.Count | Should -Be 0
        }
    }
}

Describe "Native Get-DbaDbMailProfile on Azure SQL Database" -Tag IntegrationTests {
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
        @(Get-DbaDbMailProfile -SqlInstance $azureServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        $warnings.Count | Should -Be 2
        "$($warnings[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| .*Azure SQL Database not supported"
        "$($warnings[1])" | Should -Match "\[Get-DbaDbMailProfile\] No servers to process$"
        { Get-DbaDbMailProfile -SqlInstance $azureServer -EnableException -WarningAction SilentlyContinue } | Should -Throw "No servers to process"
    }
}
