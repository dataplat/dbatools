#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbMailConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads Database Mail settings.

Describe "Native Get-DbaDbMailConfig" -Tag IntegrationTests {
    BeforeAll {
        # The legs of one SQL version share the instance; these tests only read it.
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $mail = Get-DbaDbMail -SqlInstance $instance -EnableException
        $mailTwo = Get-DbaDbMail -SqlInstance $instance -EnableException
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $settings = @($server.Query("EXEC msdb.dbo.sysmail_help_configure_sp;"))
        $bindingMessage = "Cannot bind argument to parameter 'InputObject' because it is null."
        $instanceBindingMessage = "Cannot bind argument to parameter 'SqlInstance' because it is null."

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments, [string]$Script = 'param($Arguments) Get-DbaDbMailConfig @Arguments; "next statement"')
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaDbMailConfig -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbMailConfig", $outsideType, $null
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

    Context "Output" {
        It "returns every setting as the engine reports it, in name order" {
            $result = @(Get-DbaDbMailConfig -SqlInstance $instance -EnableException)
            $settings.Count | Should -BeGreaterThan 0
            ($result.Name -join ",") | Should -BeExactly ((@($settings.paramname) | Sort-Object) -join ",")
            foreach ($row in $result) {
                $setting = $settings | Where-Object paramname -eq $row.Name
                $row.Value | Should -BeExactly ([string]$setting.paramvalue)
                $row.Description | Should -BeExactly ([string]$setting.description)
            }
        }

        It "keeps the SMO type, the instance columns and the pinned default view" {
            $result = @(Get-DbaDbMailConfig -SqlInstance $instance -EnableException)
            foreach ($row in $result) {
                $row | Should -BeOfType Microsoft.SqlServer.Management.Smo.Mail.ConfigurationValue
                $row.ComputerName | Should -Be $server.ComputerName
                $row.InstanceName | Should -Be $server.ServiceName
                $row.SqlInstance | Should -Be $server.DomainInstanceName
                ($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
                    Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,Value,Description"
            }
        }

        It "leaves the instance columns and the view of Get-DbaDbMail on the mail object behind each row" {
            $row = Get-DbaDbMailConfig -SqlInstance $instance -Name MaxFileSize -EnableException
            $row.Parent.ComputerName | Should -Be $server.ComputerName
            $row.Parent.InstanceName | Should -Be $server.ServiceName
            $row.Parent.SqlInstance | Should -Be $server.DomainInstanceName
            ($row.Parent.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
                Should -BeExactly "ComputerName,InstanceName,SqlInstance,Profiles,Accounts,ConfigurationValues,Properties"
        }

        It "stops quietly when downstream takes only the first value" {
            foreach ($enableException in $false, $true) {
                $first = @(Get-DbaDbMailConfig -SqlInstance $instance, $badInstance -EnableException:$enableException -WarningAction SilentlyContinue | Select-Object -First 1)
                $first.Count | Should -Be 1
            }
        }
    }

    Context "-Name" {
        It "matches a whole name without regard to case, and keeps the order of the collection" {
            (Get-DbaDbMailConfig -SqlInstance $instance -Name PROHIBITEDextensions -EnableException).Name | Should -BeExactly "ProhibitedExtensions"
            (@(Get-DbaDbMailConfig -SqlInstance $instance -Name ProhibitedExtensions, MaxFileSize -EnableException).Name -join ",") | Should -BeExactly "MaxFileSize,ProhibitedExtensions"
            @(Get-DbaDbMailConfig -SqlInstance $instance -Name MaxFileSize, MaxFileSize -EnableException).Count | Should -Be 1
        }

        It "gives nothing and no warning for a name no setting has, as a pattern too" {
            foreach ($value in "NoSuchSetting", "Prohibited*") {
                $warnings = @()
                @(Get-DbaDbMailConfig -SqlInstance $instance -Name $value -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
                $warnings.Count | Should -Be 0
            }
        }

        It "reads -Name by its truth, so a lone empty value filters nothing and two of them match nothing" {
            $all = $settings.Count
            @(Get-DbaDbMailConfig -SqlInstance $instance -Name "" -EnableException).Count | Should -Be $all
            @(Get-DbaDbMailConfig -SqlInstance $instance -Name @() -EnableException).Count | Should -Be $all
            @(Get-DbaDbMailConfig -SqlInstance $instance -Name $null -EnableException).Count | Should -Be $all
            @(Get-DbaDbMailConfig -SqlInstance $instance -Name "", "" -EnableException).Count | Should -Be 0
        }

        It "takes the pinned aliases and positions" {
            (Get-DbaDbMailConfig -SqlInstance $instance -Config LoggingLevel -EnableException).Name | Should -BeExactly "LoggingLevel"
            (Get-DbaDbMailConfig -SqlInstance $instance -ConfigName LoggingLevel -EnableException).Name | Should -BeExactly "LoggingLevel"
            (Get-DbaDbMailConfig $instance $null LoggingLevel -EnableException).Name | Should -BeExactly "LoggingLevel"
            (Get-DbaDbMailConfig $null $null LoggingLevel $mail -EnableException).Name | Should -BeExactly "LoggingLevel"
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
                @(Get-DbaDbMailConfig @form -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match "\[Get-DbaDbMailConfig\] No servers to process$"
            }
            $warnings = @()
            @(Get-DbaDbMailConfig -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 1
        }

        It "throws that under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaDbMailConfig -EnableException
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly "No servers to process"
            $failure.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMailConfig*"
            $failure.CategoryInfo.Category | Should -Be "NotSpecified"
            $failure.TargetObject | Should -BeNullOrEmpty
        }

        It "warns for each piped record that brings nothing, and still reads the next" {
            $warnings = @()
            @($null, $null | Get-DbaDbMailConfig -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 2

            $warnings = @()
            $result = @($null, $mail | Get-DbaDbMailConfig -Name MaxFileSize -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $result.Name | Should -BeExactly "MaxFileSize"
            $warnings.Count | Should -Be 1
        }
    }

    Context "Mail objects" {
        It "reads several mail objects, piped or named" -Tag "NativeChecklist:pipeline-multiple" {
            $piped = @($mail, $mailTwo | Get-DbaDbMailConfig -Name MaxFileSize -EnableException)
            $piped.Count | Should -Be 2
            [object]::ReferenceEquals($piped[0].Parent, $mail) | Should -BeTrue
            [object]::ReferenceEquals($piped[1].Parent, $mailTwo) | Should -BeTrue
            @(Get-DbaDbMailConfig -InputObject $mail, $mailTwo -Name MaxFileSize -EnableException).Count | Should -Be 2
            @($instance, $instance | Get-DbaDbMail -EnableException | Get-DbaDbMailConfig -Name MaxFileSize -EnableException).Count | Should -Be 2
        }

        It "puts the named instances after the input" {
            $result = @(Get-DbaDbMailConfig -InputObject $mail -SqlInstance $server -Name MaxFileSize -EnableException)
            $result.Count | Should -Be 2
            [object]::ReferenceEquals($result[0].Parent, $mail) | Should -BeTrue
            [object]::ReferenceEquals($result[1].Parent, $mail) | Should -BeFalse
        }

        It "refuses a value that is no mail object, by the pinned binding faults" {
            $failure = $null
            try {
                $null = Get-DbaDbMailConfig -InputObject "notmail"
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentTransformationError,*"
            $failure.Exception.Message | Should -BeExactly "Cannot process argument transformation on parameter 'InputObject'. Cannot convert the `"notmail`" value of type `"System.String`" to type `"Microsoft.SqlServer.Management.Smo.Mail.SqlMail[]`"."

            $errors = @()
            @("notmail" | Get-DbaDbMailConfig -ErrorAction SilentlyContinue -ErrorVariable errors).Count | Should -Be 0
            $errors.Count | Should -Be 1
            $errors[0].FullyQualifiedErrorId | Should -BeLike "InputObjectNotBound,*"
        }
    }

    Context "Failed instances" {
        It "warns as Get-DbaDbMail, then that there are no servers" {
            $warnings = @()
            @(Get-DbaDbMailConfig -SqlInstance $badInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 2
            "$($warnings[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| "
            "$($warnings[1])" | Should -Match "\[Get-DbaDbMailConfig\] No servers to process$"
        }

        It "throws only the second under -EnableException, where the pinned call never carries that switch" -Tag "NativeChecklist:enable-exception" {
            $warnings = @()
            $failure = $null
            try {
                $null = Get-DbaDbMailConfig -SqlInstance $badInstance -EnableException -WarningAction SilentlyContinue -WarningVariable warnings
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly "No servers to process"
            "$($warnings[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| "
        }

        It "warns of a failed named instance and still reads the mail objects beside it, with no error" {
            $forms = @(
                @{ InputObject = $mail },
                @{ InputObject = $mail; Name = "MaxFileSize" }
            )
            foreach ($form in $forms) {
                $warnings = @()
                $merged = @(Get-DbaDbMailConfig @form -SqlInstance $badInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings 2>&1)
                @($merged | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
                $merged.Count | Should -BeGreaterThan 0
                $warnings.Count | Should -Be 1
            }
        }

        It "reports no servers for an empty input beside a failed named instance" {
            $warnings = @()
            @(Get-DbaDbMailConfig -InputObject @() -SqlInstance $badInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            "$($warnings[1])" | Should -Match "\[Get-DbaDbMailConfig\] No servers to process$"
        }

        It "warns of a failed instance among good ones and reads the others, -EnableException or not" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
            foreach ($enableException in $false, $true) {
                $warnings = @()
                $result = @(Get-DbaDbMailConfig -SqlInstance $instance, $badInstance, $instance -Name MaxFileSize -EnableException:$enableException -WarningAction SilentlyContinue -WarningVariable warnings)
                $result.Count | Should -Be 2
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| "
            }
        }
    }

    Context "Null elements" {
        It "outside any try, a plain call writes the binding fault of the nested Get-DbaDbMail, reads no instance of that array, warns that there are no servers and goes on" {
            foreach ($value in @(@($null, $instance), @($instance, $null), @($null, $null))) {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $value; Name = "MaxFileSize" }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 1
                $outside.Errors[0].Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
                $outside.Errors[0].Exception.Message | Should -BeExactly $instanceBindingMessage
                $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $outside.Errors[0].CategoryInfo.Category | Should -Be "InvalidData"
                $outside.Errors[0].CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $outside.Errors[0].CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMail"
                $outside.Errors[0].TargetObject | Should -BeNullOrEmpty
                $outside.Warnings.Count | Should -Be 1
                $outside.Warnings[0].Message | Should -Match "\[Get-DbaDbMailConfig\] No servers to process$"
                ($outside.Output -join ",") | Should -BeExactly "next statement"
            }
        }

        It "outside any try, a plain call with a null or empty -SqlInstance only warns that there are no servers, as the pin's if reads it" {
            foreach ($form in @(@{ SqlInstance = $null }, @{ SqlInstance = @() })) {
                $outside = Invoke-NativeOutsideTry $form
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 0
                $outside.Warnings.Count | Should -Be 1
                $outside.Warnings[0].Message | Should -Match "\[Get-DbaDbMailConfig\] No servers to process$"
                ($outside.Output -join ",") | Should -BeExactly "next statement"
            }
        }

        It "outside any try, a plain call writes the fault and still reads the mail objects given beside the instances" {
            foreach ($value in @(@($null, $instance), @($instance, $null))) {
                $outside = Invoke-NativeOutsideTry @{ InputObject = $mail; SqlInstance = $value; Name = "MaxFileSize" }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 1
                $outside.Errors[0].Exception.Message | Should -BeExactly $instanceBindingMessage
                $outside.Errors[0].CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMail"
                $outside.Warnings.Count | Should -Be 0
                $outside.Output.Count | Should -Be 2
                $outside.Output[0].Name | Should -BeExactly "MaxFileSize"
                [object]::ReferenceEquals($outside.Output[0].Parent, $mail) | Should -BeTrue
                $outside.Output[1] | Should -BeExactly "next statement"
            }
        }

        It "outside any try, reports a null element of -SqlInstance once beside piped mail objects" {
            $script = 'param($Arguments) $piped = $Arguments.Piped; $null = $Arguments.Remove("Piped"); $piped | Get-DbaDbMailConfig @Arguments; "next statement"'
            $outside = Invoke-NativeOutsideTry @{ Piped = @($mail, $mailTwo); SqlInstance = @($null, $instance); Name = "MaxFileSize" } -Script $script
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.Message | Should -BeExactly $instanceBindingMessage
            $outside.Output.Count | Should -Be 3
            $outside.Output[2] | Should -BeExactly "next statement"
        }

        It "inside a caller's try, the fault stops the command and the catch receives it, with no value and no warning out" {
            foreach ($form in @(@{ SqlInstance = @($null, $instance) }, @{ SqlInstance = @($instance, $null) }, @{ SqlInstance = @($null, $null) }, @{ SqlInstance = @($null, $instance); InputObject = $mail })) {
                $streamed = New-Object System.Collections.ArrayList
                $warnings = @()
                $failure = $null
                $after = $false
                try {
                    Get-DbaDbMailConfig @form -Name MaxFileSize -WarningAction SilentlyContinue -WarningVariable warnings | ForEach-Object { $null = $streamed.Add($PSItem) }
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                $failure | Should -Not -BeNullOrEmpty
                $failure.Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
                $failure.Exception.Message | Should -BeExactly $instanceBindingMessage
                $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $failure.CategoryInfo.Category | Should -Be "InvalidData"
                $failure.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $failure.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMailConfig"
                $failure.TargetObject | Should -BeNullOrEmpty
                $after | Should -BeFalse
                $streamed.Count | Should -Be 0
                $warnings.Count | Should -Be 0
            }
        }

        It "stops at the fault only under -EnableException, with no value out" -Tag "NativeChecklist:enable-exception" {
            foreach ($form in @(@{ SqlInstance = @($null, $instance) }, @{ SqlInstance = @($instance, $null) }, @{ SqlInstance = @($null, $instance); InputObject = $mail })) {
                $streamed = New-Object System.Collections.ArrayList
                $failure = $null
                try {
                    Get-DbaDbMailConfig @form -Name MaxFileSize -EnableException | ForEach-Object { $null = $streamed.Add($PSItem) }
                } catch {
                    $failure = $PSItem
                }
                $failure.Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
                $failure.Exception.Message | Should -BeExactly $instanceBindingMessage
                $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $failure.CategoryInfo.Category | Should -Be "InvalidData"
                $failure.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $failure.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMailConfig"
                $streamed.Count | Should -Be 0
            }
        }

        It "stops at the fault under -ErrorAction Stop, with no value out" {
            foreach ($form in @(@{ SqlInstance = @($null, $instance) }, @{ SqlInstance = @($instance, $null) }, @{ SqlInstance = @($null, $instance); InputObject = $mail })) {
                $streamed = New-Object System.Collections.ArrayList
                $failure = $null
                try {
                    Get-DbaDbMailConfig @form -Name MaxFileSize -ErrorAction Stop | ForEach-Object { $null = $streamed.Add($PSItem) }
                } catch {
                    $failure = $PSItem
                }
                $failure.Exception.Message | Should -BeExactly $instanceBindingMessage
                $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $failure.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMailConfig"
                $streamed.Count | Should -Be 0
            }
        }

        It "outside any try, -EnableException ends the command at the fault and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $mail; SqlInstance = @($null, $instance); Name = "MaxFileSize"; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.Message | Should -BeExactly $instanceBindingMessage
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
            $outside.Errors[0].CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMail"
            $outside.Warnings.Count | Should -Be 0
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "outside any try, -ErrorAction Stop turns the fault into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $mail; SqlInstance = @($null, $instance); Name = "MaxFileSize"; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Stop.ErrorRecord.Exception.Message | Should -BeExactly $instanceBindingMessage
            $outside.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
            $outside.Stop.ErrorRecord.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbMailConfig"
            $outside.Output.Count | Should -Be 0
        }

        It "writes one fault per pinned decoration for a null mail object, and reads the next" {
            foreach ($enableException in $false, $true) {
                $errors = @()
                $result = @(Get-DbaDbMailConfig -InputObject @($null, $mail) -EnableException:$enableException -ErrorAction SilentlyContinue -ErrorVariable errors)
                $result.Count | Should -Be $settings.Count
                @($errors | Where-Object { $PSItem.Exception.Message -ceq $bindingMessage }).Count | Should -Be 3
                $errors[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                $errors[0].CategoryInfo.Category | Should -Be "InvalidData"
                $errors[0].CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
            }
        }

        It "warns of a null mail object under -ErrorAction Stop, where the function's own catch takes the fault, and reads the next" {
            $warnings = @()
            $result = @(Get-DbaDbMailConfig -InputObject @($null, $mail) -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable warnings)
            $result.Count | Should -Be $settings.Count
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaDbMailConfig\] Failure \| " + [regex]::Escape($bindingMessage) + "$")

            $warnings = @()
            @(Get-DbaDbMailConfig -InputObject @($null, $null) -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 2
        }

        It "throws that catch's record under -ErrorAction Stop and -EnableException" -Tag "NativeChecklist:enable-exception" {
            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            try {
                Get-DbaDbMailConfig -InputObject @($null, $mail) -ErrorAction Stop -EnableException | ForEach-Object { $null = $streamed.Add($PSItem) }
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $failure.Exception.Message | Should -BeExactly $bindingMessage
            $failure.Exception.InnerException | Should -BeOfType System.Management.Automation.ParameterBindingException
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMailConfig*"
            $failure.CategoryInfo.Category | Should -Be "InvalidData"
            $failure.TargetObject | Should -BeNullOrEmpty
            $streamed.Count | Should -Be 0
        }

        It "passes a null mail object in silence under -Name" {
            $errors = @()
            $result = @(Get-DbaDbMailConfig -InputObject @($mail, $null) -Name MaxFileSize -ErrorAction SilentlyContinue -ErrorVariable errors)
            $result.Name | Should -BeExactly "MaxFileSize"
            $errors.Count | Should -Be 0
        }
    }

    Context "Corrections" {
        It "reports the instance columns of a mail object read straight from a server" {
            $raw = (Connect-DbaInstance -SqlInstance $instance -EnableException).Mail
            foreach ($row in @($raw | Get-DbaDbMailConfig -Name MaxFileSize -EnableException), @(Get-DbaDbMailConfig -InputObject $raw -Name MaxFileSize -EnableException)) {
                $row.ComputerName | Should -Be $server.ComputerName
                $row.InstanceName | Should -Be $server.ServiceName
                $row.SqlInstance | Should -Be $server.DomainInstanceName
            }
        }

        It "reads a named instance once beside piped mail objects" {
            $warnings = @()
            $beside = @($mail, $mailTwo | Get-DbaDbMailConfig -SqlInstance $instance -Name MaxFileSize -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $beside.Count | Should -Be 3
            $warnings.Count | Should -Be 0

            $warnings = @()
            $afterNulls = @($null, $null | Get-DbaDbMailConfig -SqlInstance $instance -Name MaxFileSize -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $afterNulls.Count | Should -Be 1
            $warnings.Count | Should -Be 0
        }
    }
}

Describe "Native Get-DbaDbMailConfig over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        # sqlwhale22 is shared: the login name is unique per leg and run, and no test changes a mail setting there.
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        $lowName = "dbatoolsci_nmc_$(Get-Random)"
        $lowPassword = "Nmc-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        $deniedMessage = "The EXECUTE permission was denied on the object 'sysmail_help_configure_sp', database 'msdb', schema 'dbo'."
        $localMail = Get-DbaDbMail -SqlInstance $TestConfig.InstanceSingle -EnableException
    }

    AfterAll {
        $null = $loginServer.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$lowName'; EXEC sys.sp_executesql @kill;")
        $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaDbMailConfig -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            $result.Count | Should -BeGreaterThan 0
            $result[0].SqlInstance | Should -Be $loginServer.DomainInstanceName
        }

        It "warns without the credential, as the nested Get-DbaDbMail does" {
            $warnings = @()
            @(Get-DbaDbMailConfig -SqlInstance $loginInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 2
            "$($warnings[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| Login failed"
            "$($warnings[1])" | Should -Match "\[Get-DbaDbMailConfig\] No servers to process$"
        }

        It "throws only that there are no servers under -EnableException" {
            $failure = $null
            try {
                $null = Get-DbaDbMailConfig -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly "No servers to process"
        }
    }

    Context "A failed read" {
        It "warns of a login that cannot read the settings, with or without -Name" {
            foreach ($form in @{ }, @{ Name = "MaxFileSize" }) {
                $warnings = @()
                @(Get-DbaDbMailConfig -SqlInstance $loginInstance -SqlCredential $lowCred @form -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match ("\[Get-DbaDbMailConfig\] Failure \| " + [regex]::Escape($deniedMessage) + "$")
            }
        }

        It "throws the pinned record under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaDbMailConfig -SqlInstance $loginInstance -SqlCredential $lowCred -EnableException
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $failure.Exception.Message | Should -BeExactly $deniedMessage
            $failure.Exception.InnerException.GetType().FullName | Should -BeExactly "Microsoft.Data.SqlClient.SqlException"
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMailConfig*"
            $failure.CategoryInfo.Category | Should -Be "NotSpecified"
            $failure.TargetObject | Should -BeNullOrEmpty
        }

        It "goes on to the next mail object, and stops there under -EnableException" -Tag "NativeChecklist:multi-instance-failure" {
            $lowMail = Get-DbaDbMail -SqlInstance $loginInstance -SqlCredential $lowCred -EnableException
            $warnings = @()
            $result = @($lowMail, $localMail | Get-DbaDbMailConfig -Name MaxFileSize -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $result.Count | Should -Be 1
            $warnings.Count | Should -Be 1

            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            try {
                $lowMail, $localMail | Get-DbaDbMailConfig -Name MaxFileSize -EnableException | ForEach-Object { $null = $streamed.Add($PSItem) }
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly $deniedMessage
            $streamed.Count | Should -Be 0
        }
    }
}

Describe "Native Get-DbaDbMailConfig on Azure SQL Database" -Tag IntegrationTests {
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
        @(Get-DbaDbMailConfig -SqlInstance $azureServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        $warnings.Count | Should -Be 2
        "$($warnings[0])" | Should -Match "\[Get-DbaDbMail\] Failure \| .*Azure SQL Database not supported"
        "$($warnings[1])" | Should -Match "\[Get-DbaDbMailConfig\] No servers to process$"
        { Get-DbaDbMailConfig -SqlInstance $azureServer -EnableException -WarningAction SilentlyContinue } | Should -Throw "No servers to process"
    }
}
