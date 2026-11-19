#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: pipeline-multiple N/A -- the command takes no pipeline input; every parameter binds by name or position.
# NativeChecklist: multi-instance-failure N/A -- the command has no instance parameter and opens no SQL Server connection.
# NativeChecklist: whatif-confirm N/A -- the command does not support ShouldProcess; it requests tokens and changes no state.
# NativeChecklist: azure-sqldb N/A -- the command opens no SQL Server connection; it asks Microsoft Entra ID or the Azure Instance Metadata Service for a token.
# NativeChecklist: sql-login N/A -- the pinned function has no SqlCredential; -Credential is a service principal's application id and secret.
# NativeSkip: New-DbaAzAccessToken -- covered: Native New-DbaAzAccessToken.When the token request fails.warns Failure without eating an iteration of the caller's loop
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaAzAccessToken",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native New-DbaAzAccessToken" -Tag IntegrationTests {
    BeforeAll {
        # A tenant that does not exist: Microsoft Entra ID answers every request for it with an AADSTS error.
        $badTenant = "dbatoolsci.invalid"
        $badPassword = ConvertTo-SecureString -String "dbatoolsci" -AsPlainText -Force
        $badCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "dbatoolsci", $badPassword
    }

    Context "When the token request fails" {
        It "warns Failure when the Instance Metadata Service does not answer" {
            # The lab machines are not Azure VMs, so the managed identity request fails inside the try on both editions.
            $splatManagedIdentity = @{
                Type            = "ManagedIdentity"
                WarningAction   = "SilentlyContinue"
                WarningVariable = "managedIdentityWarnings"
            }
            $result = New-DbaAzAccessToken @splatManagedIdentity
            $result | Should -BeNullOrEmpty
            ($managedIdentityWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "keeps the web request's InvalidOperation category and transport exception when the Instance Metadata Service does not answer" {
            # The pin's Invoke-WebRequest raises WebCmdletWebResponseException (InvalidOperation) around a WebException on
            # Windows PowerShell and an HttpRequestException on PowerShell 7; Stop-Function keeps both (probe pin-azfaults-20261111).
            $thrown = $null
            try {
                $null = New-DbaAzAccessToken -Type ManagedIdentity -EnableException
            } catch {
                $thrown = $PSItem
            }
            $thrown | Should -Not -BeNullOrEmpty
            $thrown.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
            if ($PSVersionTable.PSEdition -eq "Core") {
                $thrown.Exception.InnerException | Should -BeOfType [System.Net.Http.HttpRequestException]
            } else {
                $thrown.Exception.InnerException | Should -BeOfType [System.Net.WebException]
            }
        }

        It "throws with EnableException and only warns without it" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            $splatBadTenant = @{
                Type       = "ServicePrincipal"
                Tenant     = $badTenant
                Credential = $badCredential
            }
            { New-DbaAzAccessToken @splatBadTenant -EnableException } | Should -Throw

            $result = New-DbaAzAccessToken @splatBadTenant -EnableException:$false -WarningAction SilentlyContinue -WarningVariable quietWarnings
            $result | Should -BeNullOrEmpty
            $quietWarnings | Should -Not -BeNullOrEmpty
        }

        It "warns that a Credential and Tenant are needed when both are missing" {
            $splatNoIdentity = @{
                Type            = "ServicePrincipal"
                Tenant          = ""
                WarningAction   = "SilentlyContinue"
                WarningVariable = "guardWarnings"
            }
            $result = New-DbaAzAccessToken @splatNoIdentity
            $result | Should -BeNullOrEmpty
            ($guardWarnings -join " ") | Should -BeLike "*You must specify a Credential and Tenant when using ServicePrincipal or RenewableServicePrincipal*"
        }

        It "warns Failure without eating an iteration of the caller's loop" {
            # A Tenant without a Credential fails inside the process block's try on both editions, with no network.
            # The catch must not run a continue that escapes the command and consumes an iteration of this loop
            # (#10638), the behaviour the pinned Windows PowerShell test checks.
            $loopCount = 0
            $loopWarnings = @()
            foreach ($i in 1..3) {
                $splatTenantOnly = @{
                    Type            = "RenewableServicePrincipal"
                    Tenant          = $badTenant
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "+loopWarnings"
                }
                $result = New-DbaAzAccessToken @splatTenantOnly
                $result | Should -BeNullOrEmpty
                $loopCount++
            }
            $loopCount | Should -Be 3
            $loopWarnings.Count | Should -Be 3
            foreach ($warning in $loopWarnings) {
                "$warning" | Should -BeLike "*Failure*You cannot call a method on a null-valued expression*"
            }
        }

        It "stops with PowerShell's InvalidOperation null-method record when only a Tenant is given" {
            $thrown = $null
            try {
                $null = New-DbaAzAccessToken -Type RenewableServicePrincipal -Tenant $badTenant -EnableException
            } catch {
                $thrown = $PSItem
            }
            $thrown | Should -Not -BeNullOrEmpty
            $thrown.CategoryInfo.Category | Should -Be "InvalidOperation"
            $thrown.Exception.Message | Should -BeLike "*You cannot call a method on a null-valued expression*"
        }
    }

    Context "When the configured client secret is not a SecureString" {
        BeforeAll {
            # The pin builds a credential from azure.appid and azure.clientsecret with New-Object PSCredential, outside any
            # try. A plain-string secret (set past the securestring validation) fails that statement with New-Object's
            # record; the pin then goes on without a credential. The configuration is process-wide, so the runspace below
            # sees it too; AfterAll puts both values back.
            $oldAppId = Get-DbatoolsConfigValue -FullName azure.appid
            $oldSecret = Get-DbatoolsConfigValue -FullName azure.clientsecret
            Set-DbatoolsConfig -FullName azure.appid -Value "dbatoolsci-appid"
            Set-DbatoolsConfig -FullName azure.clientsecret -Value "dbatoolsci-plain" -DisableValidation

            # The pinned record belongs to New-Object, a child command of the pinned function: its id is
            # ConstructorInvokedThrowException,Microsoft.PowerShell.Commands.NewObjectCommand (manager probe
            # ctor-owner-record-20261112 r2, pin stage, both editions: evidence ctor-owner-record-r2-20261112.txt).
            # harness-edits.md, "Child-command error owner and further checks by the manager (operator, 2026-11-12)",
            # Part A: the port's record carries the same id with its own cmdlet type in place of the child's (point 1),
            # everything else exact (point 2), and this Context asserts the full id and compares the rest with the pinned
            # record on the same leg (point 3). The pinned record is New-Object's own record for the pinned statement
            # (the probe's newObjectReference case equals the pinned function's record field by field on both editions),
            # so the reference is that statement, run at the top level of a fresh runspace on this leg.
            $pinnedId = "ConstructorInvokedThrowException,Microsoft.PowerShell.Commands.NewObjectCommand"
            $nativeId = "ConstructorInvokedThrowException,Dataplat.Dbatools.Commands.NewDbaAzAccessTokenCommand"
            $referenceState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $referenceRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($referenceState)
            $referenceShell = [System.Management.Automation.PowerShell]::Create()
            try {
                $referenceRunspace.Open()
                $referenceShell.Runspace = $referenceRunspace
                $null = $referenceShell.AddScript('$appid = "dbatoolsci-appid"; $clientsecret = "dbatoolsci-plain"; $Credential = New-Object System.Management.Automation.PSCredential ($appid, $clientsecret); "next statement"')
                $referenceOutput = @($referenceShell.Invoke())
                $referenceRecords = @($referenceShell.Streams.Error)
            } finally {
                $referenceShell.Dispose()
                $referenceRunspace.Dispose()
            }

            function Get-NativeExceptionChain {
                param($Exception)
                $chain = @()
                while ($null -ne $Exception) {
                    $chain += "$($Exception.GetType().FullName): $($Exception.Message)"
                    $Exception = $Exception.InnerException
                }
                , $chain
            }

            # Point 1: the full id with the port's suffix. Point 2: every other field of the pinned record. CategoryInfo's
            # Activity and the InvocationInfo name the owner (New-Object in the pin), so they follow point 1.
            function Assert-NativeConstructorFault {
                param($Record)
                $reference = $referenceRecords[0]
                $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $Record.FullyQualifiedErrorId | Should -BeExactly $nativeId
                $Record.Exception.GetType().FullName | Should -BeExactly $reference.Exception.GetType().FullName
                $Record.Exception.Message | Should -BeExactly $reference.Exception.Message
                $Record.CategoryInfo.Category | Should -Be $reference.CategoryInfo.Category
                $Record.CategoryInfo.Reason | Should -BeExactly $reference.CategoryInfo.Reason
                $Record.CategoryInfo.TargetName | Should -BeExactly $reference.CategoryInfo.TargetName
                $Record.CategoryInfo.TargetType | Should -BeExactly $reference.CategoryInfo.TargetType
                $Record.TargetObject | Should -Be $reference.TargetObject
                "$($Record.ErrorDetails)" | Should -BeExactly "$($reference.ErrorDetails)"
                ((Get-NativeExceptionChain $Record.Exception) -join " <- ") | Should -BeExactly ((Get-NativeExceptionChain $reference.Exception) -join " <- ")
            }

            # harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5: the port's own
            # complete -ErrorVariable and $Error sequences, entry by entry with type and id, for each mode. Measured on
            # both editions by the manager's probe of the native stage at 1167ecbc3 (evidence
            # ctor-owner-record-native-am3-20261112.txt); the runspace is fresh, so both start empty, and $Error lists
            # the newest entry first. The pin's entries (the engine's CmdletInvocationException wrapper, repeated copies
            # and the caught InvokeMethodOnNull entries, points 2 and 3) are listed next to these in the item notes
            # (point 6).
            $nullCallChain = @(
                "System.Exception: You cannot call a method on a null-valued expression.",
                "System.Management.Automation.RuntimeException: You cannot call a method on a null-valued expression."
            )
            $noTenantChain = @("System.Exception: You must specify a Credential and Tenant when using ServicePrincipal or RenewableServicePrincipal")

            # The record of the pin's Stop-Function that goes on ("Engine error records in native ports", point 4): the
            # shared StopFunction's record, id dbatools_New-DbaAzAccessToken, empty Activity, no ErrorDetails, with the
            # pin's exception type, message, category, reason, target and inner chain (probe r2, both editions; no live
            # reference exists for Stop-Function's record, so the probe's values).
            function Assert-NativeStopRecord {
                param($Record, $Category, [string[]]$Chain)
                $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $Record.FullyQualifiedErrorId | Should -BeExactly "dbatools_New-DbaAzAccessToken"
                $Record.CategoryInfo.Activity | Should -BeNullOrEmpty
                $Record.ErrorDetails | Should -BeNullOrEmpty
                $Record.Exception.GetType().FullName | Should -BeExactly "System.Exception"
                $Record.CategoryInfo.Category | Should -Be $Category
                $Record.CategoryInfo.Reason | Should -BeExactly "Exception"
                $Record.CategoryInfo.TargetName | Should -BeExactly ""
                $Record.CategoryInfo.TargetType | Should -BeExactly ""
                $Record.TargetObject | Should -BeNullOrEmpty
                ((Get-NativeExceptionChain $Record.Exception) -join " <- ") | Should -BeExactly ($Chain -join " <- ")
            }

            # A call that goes on (plain, merged streams, -ErrorAction SilentlyContinue): -ErrorVariable holds the
            # record, then the stop record; $Error holds the stop record, then the record.
            function Assert-NativeGoesOnEntries {
                param($Outside, $Category, [string[]]$Chain)
                $Outside.ErrorVariable.Count | Should -Be 2
                Assert-NativeConstructorFault -Record $Outside.ErrorVariable[0]
                Assert-NativeStopRecord -Record $Outside.ErrorVariable[1] -Category $Category -Chain $Chain
                $Outside.DollarError.Count | Should -Be 2
                Assert-NativeStopRecord -Record $Outside.DollarError[0] -Category $Category -Chain $Chain
                Assert-NativeConstructorFault -Record $Outside.DollarError[1]
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own. The helper
            # names -ErrorVariable nativeEv on the call and reads that runspace's $Error and nativeEv back afterwards.
            function Invoke-NativeTokenOutsideTry {
                param([hashtable]$Arguments, [switch]$Merged, [switch]$CallerTry)
                $outsideScript = 'param($Arguments) New-DbaAzAccessToken @Arguments -ErrorVariable nativeEv; "next statement"'
                if ($Merged) {
                    $outsideScript = 'param($Arguments) New-DbaAzAccessToken @Arguments -ErrorVariable nativeEv 2>&1 3>&1; "next statement"'
                }
                if ($CallerTry) {
                    $outsideScript = 'param($Arguments) try { New-DbaAzAccessToken @Arguments -ErrorVariable nativeEv; "after the command" } catch { $PSItem; "caught" }; "next statement"'
                }
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command New-DbaAzAccessToken -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "New-DbaAzAccessToken", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $readShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript($outsideScript).AddArgument($Arguments)
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        $outsideStop = $PSItem.Exception.InnerException
                    }
                    $readShell.Runspace = $outsideRunspace
                    $null = $readShell.AddScript('[pscustomobject]@{ Errors = @($global:Error); Variable = @($global:nativeEv) }')
                    $readBack = @($readShell.Invoke())[0]
                    [pscustomobject]@{
                        Output        = @($outsideOutput)
                        Errors        = @($outsideShell.Streams.Error)
                        Warnings      = @($outsideShell.Streams.Warning)
                        Stop          = $outsideStop
                        DollarError   = @($readBack.Errors)
                        ErrorVariable = @($readBack.Variable)
                    }
                } finally {
                    $readShell.Dispose()
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }
        }

        AfterAll {
            Set-DbatoolsConfig -FullName azure.appid -Value $oldAppId -DisableValidation
            Set-DbatoolsConfig -FullName azure.clientsecret -Value $oldSecret -DisableValidation
        }

        It "measures the pinned statement's own record on this leg as the reference" {
            ($referenceOutput -join ",") | Should -BeExactly "next statement"
            $referenceRecords.Count | Should -Be 1
            $referenceRecords[0].FullyQualifiedErrorId | Should -BeExactly $pinnedId
        }

        It "writes New-Object's record and goes on without a credential, outside any try" {
            # Probe r2 plainRenewable: the record, then the Failure warning; the caller's next statement runs.
            $outside = Invoke-NativeTokenOutsideTry @{ Type = "RenewableServicePrincipal"; Tenant = $badTenant }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeConstructorFault -Record $outside.Errors[0]
            $outside.Warnings.Count | Should -Be 1
            "$($outside.Warnings[0])" | Should -BeLike "*Failure*You cannot call a method on a null-valued expression*"
            ($outside.Output -join ",") | Should -BeExactly "next statement"
            Assert-NativeGoesOnEntries -Outside $outside -Category InvalidOperation -Chain $nullCallChain
        }

        It "goes on to the Credential and Tenant check, outside any try" {
            # Probe r2 plainNoTenant.
            $outside = Invoke-NativeTokenOutsideTry @{ Type = "ServicePrincipal"; Tenant = "" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeConstructorFault -Record $outside.Errors[0]
            $outside.Warnings.Count | Should -Be 1
            "$($outside.Warnings[0])" | Should -BeLike "*You must specify a Credential and Tenant when using ServicePrincipal or RenewableServicePrincipal*"
            ($outside.Output -join ",") | Should -BeExactly "next statement"
            Assert-NativeGoesOnEntries -Outside $outside -Category NotSpecified -Chain $noTenantChain
        }

        It "writes New-Object's record before the warning, outside any try" {
            # Probe r2 orderRenewable and orderNoTenant: with the error and warning streams merged, the record comes first.
            $orderCases = @(
                @{ Splat = @{ Type = "RenewableServicePrincipal"; Tenant = $badTenant }; Category = "InvalidOperation"; Chain = $nullCallChain },
                @{ Splat = @{ Type = "ServicePrincipal"; Tenant = "" }; Category = "NotSpecified"; Chain = $noTenantChain }
            )
            foreach ($orderCase in $orderCases) {
                $outside = Invoke-NativeTokenOutsideTry $orderCase.Splat -Merged
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Output.Count | Should -Be 3
                Assert-NativeConstructorFault -Record $outside.Output[0]
                $outside.Output[1] | Should -BeOfType [System.Management.Automation.WarningRecord]
                "$($outside.Output[2])" | Should -BeExactly "next statement"
                Assert-NativeGoesOnEntries -Outside $outside -Category $orderCase.Category -Chain $orderCase.Chain
            }
        }

        It "keeps New-Object's record in `$Error and -ErrorVariable without showing it under -ErrorAction SilentlyContinue" {
            # Probe r2 silentRenewable: no error stream, the Failure warning, the next statement runs, and the record is
            # kept where it is kept without SilentlyContinue.
            $outside = Invoke-NativeTokenOutsideTry @{ Type = "RenewableServicePrincipal"; Tenant = $badTenant; ErrorAction = "SilentlyContinue" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 1
            "$($outside.Warnings[0])" | Should -BeLike "*Failure*You cannot call a method on a null-valued expression*"
            ($outside.Output -join ",") | Should -BeExactly "next statement"
            Assert-NativeGoesOnEntries -Outside $outside -Category InvalidOperation -Chain $nullCallChain
        }

        It "stops at New-Object's record under -EnableException" -Tag "NativeChecklist:enable-exception" {
            # The pin's raw New-Object fault does not stop under -EnableException (probe r2 enableRenewable: the record,
            # the Failure warning, then Stop-Function's throw). This is a caller-try site, and harness-edits.md "Operator
            # decision: keep going unless -EnableException (2026-11-01)", point 3, has the port call
            # ThrowTerminatingError with the record under -EnableException; "The -ErrorVariable entry of a native
            # -EnableException stop (operator, 2026-11-06)" gives that stop's -ErrorVariable entry (point 2) and the tests
            # it needs (point 5): one CmdletInvocationException whose ErrorRecord equals the pinned record by content,
            # $Error[0] the record itself.
            $outside = Invoke-NativeTokenOutsideTry @{ Type = "RenewableServicePrincipal"; Tenant = $badTenant; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeConstructorFault -Record $outside.Errors[0]
            $outside.Warnings.Count | Should -Be 0
            ($outside.Output -join ",") | Should -BeExactly "next statement"
            $outside.ErrorVariable.Count | Should -Be 1
            $outside.ErrorVariable[0] | Should -BeOfType [System.Management.Automation.CmdletInvocationException]
            Assert-NativeConstructorFault -Record $outside.ErrorVariable[0].ErrorRecord
            $outside.DollarError.Count | Should -Be 1
            Assert-NativeConstructorFault -Record $outside.DollarError[0]
        }

        It "stops at New-Object's record under -ErrorAction Stop, outside a try" {
            # Probe r2 stopRenewable: the call stops at the record, with no warning and no further statement. The pin's
            # stop arrives as a CmdletInvocationException around the record; for the port, "keep going unless
            # -EnableException" point 3 keeps the effect PowerShell gives WriteError under -ErrorAction Stop, and
            # "Engine error records in native ports" point 2 makes the engine's ActionPreferenceStopException the stop's
            # entry.
            $outside = Invoke-NativeTokenOutsideTry @{ Type = "RenewableServicePrincipal"; Tenant = $badTenant; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeConstructorFault -Record $outside.Stop.ErrorRecord
            $outside.Warnings.Count | Should -Be 0
            $outside.Output.Count | Should -Be 0
            $outside.ErrorVariable.Count | Should -Be 1
            $outside.ErrorVariable[0] | Should -BeOfType [System.Management.Automation.ActionPreferenceStopException]
            Assert-NativeConstructorFault -Record $outside.ErrorVariable[0].ErrorRecord
            $outside.DollarError.Count | Should -Be 2
            $outside.DollarError[0] | Should -BeOfType [System.Management.Automation.ActionPreferenceStopException]
            Assert-NativeConstructorFault -Record $outside.DollarError[0].ErrorRecord
            Assert-NativeConstructorFault -Record $outside.DollarError[1]
        }

        It "lets a caller's try catch New-Object's record, with and without -EnableException" {
            # Probe r2 callerTryRenewable and callerTryEnableRenewable: the catch gets the record, nothing after the call
            # in the try runs, no warning, and $Error[0] is the record. -ErrorVariable holds the engine's
            # CmdletInvocationException around the record ("Engine error records in native ports" point 2).
            foreach ($splatTry in @(@{ Type = "RenewableServicePrincipal"; Tenant = $badTenant }, @{ Type = "RenewableServicePrincipal"; Tenant = $badTenant; EnableException = $true })) {
                $outside = Invoke-NativeTokenOutsideTry $splatTry -CallerTry
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 0
                $outside.Warnings.Count | Should -Be 0
                $outside.Output.Count | Should -Be 3
                Assert-NativeConstructorFault -Record $outside.Output[0]
                ($outside.Output[1..2] -join ",") | Should -BeExactly "caught,next statement"
                $outside.ErrorVariable.Count | Should -Be 1
                $outside.ErrorVariable[0] | Should -BeOfType [System.Management.Automation.CmdletInvocationException]
                Assert-NativeConstructorFault -Record $outside.ErrorVariable[0].ErrorRecord
                $outside.DollarError.Count | Should -Be 1
                Assert-NativeConstructorFault -Record $outside.DollarError[0]
            }
        }

        It "lets a caller's try catch New-Object's record" {
            $callerWarnings = @()
            $callerOutput = @(try { New-DbaAzAccessToken -Type RenewableServicePrincipal -Tenant $badTenant -WarningAction SilentlyContinue -WarningVariable callerWarnings; "after" } catch { $_ })
            $callerOutput.Count | Should -Be 1
            $callerOutput[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            Assert-NativeConstructorFault -Record $callerOutput[0]
            $callerWarnings.Count | Should -Be 0
        }
    }

    Context "When a service principal asks for a token" {
        It "asks the tenant's token endpoint on both editions and warns with Microsoft Entra ID's answer" {
            # The pinned Windows PowerShell loop test, run on both editions: each request really reaches Microsoft
            # Entra ID, which answers a tenant that does not exist with an AADSTS error.
            $loopCount = 0
            $loopWarnings = @()
            foreach ($i in 1..3) {
                $splatBadTenant = @{
                    Type            = "ServicePrincipal"
                    Tenant          = $badTenant
                    Credential      = $badCredential
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "+loopWarnings"
                }
                $result = New-DbaAzAccessToken @splatBadTenant
                $result | Should -BeNullOrEmpty
                $loopCount++
            }
            $loopCount | Should -Be 3
            $loopWarnings.Count | Should -Be 3
            foreach ($warning in $loopWarnings) {
                "$warning" | Should -BeLike "*Failure*AADSTS*"
            }
        }
    }

    Context "When a renewable service principal token is built" {
        It "returns a renewable token that asks Microsoft Entra ID on every renewal" {
            $splatRenewable = @{
                Type       = "RenewableServicePrincipal"
                Tenant     = $badTenant
                Credential = $badCredential
            }
            $token = New-DbaAzAccessToken @splatRenewable
            $token.GetType().FullName | Should -Be "PsObjectIRenewableToken"
            $token -is [Microsoft.SqlServer.Management.Common.IRenewableToken] | Should -BeTrue
            $token.Resource | Should -Be "https://database.windows.net/"
            $token.Tenant | Should -Be $badTenant
            $token.UserId | Should -Be "dbatoolsci"
            $token.ClientSecret | Should -Be "dbatoolsci"
            { $token.GetAccessToken() } | Should -Throw "*AADSTS*"
        }

        It "starts with TokenExpiry at the DateTimeOffset minimum" {
            $splatRenewable = @{
                Type       = "RenewableServicePrincipal"
                Tenant     = $badTenant
                Credential = $badCredential
            }
            $token = New-DbaAzAccessToken @splatRenewable
            $token.TokenExpiry | Should -Be ([System.DateTimeOffset]::MinValue)
        }

        It "asks for the resource of the Subtype" {
            $splatKeyVault = @{
                Type       = "RenewableServicePrincipal"
                Subtype    = "KeyVault"
                Tenant     = $badTenant
                Credential = $badCredential
            }
            $token = New-DbaAzAccessToken @splatKeyVault
            $token.Resource | Should -Be "https://vault.azure.net/"
        }

        It "asks for the resource a Config names" {
            $splatCustomResource = @{
                Type       = "RenewableServicePrincipal"
                Config     = @{ Resource = "https://dbatoolsci.example/" }
                Tenant     = $badTenant
                Credential = $badCredential
            }
            $token = New-DbaAzAccessToken @splatCustomResource
            $token.Resource | Should -Be "https://dbatoolsci.example/"
        }
    }
}
