#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgListener",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads availability group listeners.
# Azure SQL Database: availability groups and their listeners do not exist there (https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server#t-sql-syntax-not-supported-in-azure-sql-database: high availability is built in, and T-SQL statements related to availability groups are not supported); the command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does (correction azure-unsupported), tested below.

Describe "Get-DbaAgListener native" -Tag IntegrationTests {
    BeforeAll {
        $hadrInstance = $TestConfig.InstanceHadr
        $random = Get-Random
        $octet = Get-Random -Minimum 2 -Maximum 250

        # Own CLUSTER_TYPE NONE availability groups with unique names, as the pinned test builds one; AG01 is never touched.
        $agNameA = "dbatoolsci_aglsn_a_$random"
        $agNameB = "dbatoolsci_aglsn_b_$random"
        $listenerA = "dbatoolsci_lsn_a_$random"
        $listenerB = "dbatoolsci_lsn_b_$random"
        $missingHost = "dbatoolsci-nohost-$random"

        # Only an endpoint this file creates is removed again.
        $endpointExisted = @(Get-DbaEndpoint -SqlInstance $hadrInstance -Type DatabaseMirroring -EnableException).Count -gt 0

        $splatAg = @{
            Primary         = $hadrInstance
            Name            = $agNameA
            ClusterType     = "None"
            FailoverMode    = "Manual"
            Certificate     = "dbatoolsci_AGCert"
            EnableException = $true
        }
        $null = New-DbaAvailabilityGroup @splatAg
        $splatAg.Name = $agNameB
        $null = New-DbaAvailabilityGroup @splatAg

        $splatListenerA = @{
            SqlInstance       = $hadrInstance
            AvailabilityGroup = $agNameA
            Name              = $listenerA
            IPAddress         = "127.0.21.$octet"
            Port              = 14341
            EnableException   = $true
        }
        $null = Add-DbaAgListener @splatListenerA
        $splatListenerB = @{
            SqlInstance       = $hadrInstance
            AvailabilityGroup = $agNameB
            Name              = $listenerB
            IPAddress         = "127.0.22.$octet"
            Port              = 14342
            EnableException   = $true
        }
        $null = Add-DbaAgListener @splatListenerB

        $hadrServer = Connect-DbaInstance -SqlInstance $hadrInstance -EnableException
    }

    AfterAll {
        # Every step runs even when an earlier one fails.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB -Confirm:$false
        if (-not $endpointExisted) {
            $null = Get-DbaEndpoint -SqlInstance $hadrInstance -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
        }
    }

    Context "Listeners of the availability groups" {
        It "returns the listener with its availability group, port, instance and the pinned default display set" {
            $results = @(Get-DbaAgListener -SqlInstance $hadrInstance -AvailabilityGroup $agNameA)
            $results | Should -HaveCount 1
            $results[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener
            $results[0].Name | Should -BeExactly $listenerA
            $results[0].PortNumber | Should -Be 14341
            $results[0].AvailabilityGroup | Should -BeExactly $agNameA
            $results[0].ComputerName | Should -Be $hadrServer.ComputerName
            $results[0].InstanceName | Should -Be $hadrServer.ServiceName
            $results[0].SqlInstance | Should -Be $hadrServer.DomainInstanceName
            $defaultView = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            @($defaultView) | Should -Be @("ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "Name", "PortNumber", "ClusterIPConfiguration")
        }

        It "filters with -Listener case-insensitively, as -contains does" {
            $results = @(Get-DbaAgListener -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB -Listener $listenerB.ToUpperInvariant())
            ($results.Name -join ",") | Should -BeExactly $listenerB
            @(Get-DbaAgListener -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB -Listener "dbatoolsci_lsn_none_$random").Count | Should -Be 0
        }

        It "accepts availability groups from the pipeline" -Tag NativeChecklist:pipeline-multiple {
            $results = @(Get-DbaAvailabilityGroup -SqlInstance $hadrInstance -AvailabilityGroup $agNameA, $agNameB | Get-DbaAgListener)
            (($results.Name | Sort-Object) -join ",") | Should -BeExactly "$listenerA,$listenerB"
            ($results | Where-Object Name -eq $listenerB).AvailabilityGroup | Should -BeExactly $agNameB
        }
    }

    Context "Availability group wildcards" {
        It "matches -AvailabilityGroup wildcards, as the help documents" {
            $results = @(Get-DbaAgListener -SqlInstance $hadrInstance -AvailabilityGroup "dbatoolsci_aglsn_?_$random" -WarningVariable wildcardWarnings -WarningAction SilentlyContinue)
            $wildcardWarnings | Should -BeNullOrEmpty
            (($results.Name | Sort-Object) -join ",") | Should -BeExactly "$listenerA,$listenerB"
            $onlyA = @(Get-DbaAgListener -SqlInstance $hadrInstance -AvailabilityGroup "DBATOOLSCI_AGLSN_A*_$random")
            ($onlyA.Name -join ",") | Should -BeExactly $listenerA
            ($onlyA.AvailabilityGroup -join ",") | Should -BeExactly $agNameA
        }
    }

    Context "An instance that cannot be reached" -Tag NativeChecklist:multi-instance-failure {
        It "warns for that instance and returns the other's listeners" {
            $results = @(Get-DbaAgListener -SqlInstance $missingHost, $hadrInstance -AvailabilityGroup $agNameA -WarningVariable reachWarnings -WarningAction SilentlyContinue)
            ($results.Name -join ",") | Should -BeExactly $listenerA
            # The pin's two lines, in its order (probe errvar-pin-port-20261117, both editions): the nested lookup's
            # Connect-DbaInstance first, then the lookup's own Stop-Function.
            $reachWarnings | Should -HaveCount 2
            "$($reachWarnings[0])" | Should -Match ('\[Connect-DbaInstance\] Failure \| Error connecting to \[' + [regex]::Escape($missingHost) + '\]: ')
            "$($reachWarnings[1])" | Should -Match '\[Get-DbaAvailabilityGroup\] Failure \| '
        }

        It "warns and returns nothing when the only instance cannot be reached" {
            $results = @(Get-DbaAgListener -SqlInstance $missingHost -WarningVariable onlyWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            "$onlyWarnings" | Should -BeLike "*Get-DbaAvailabilityGroup*Failure*"
        }

        It "throws the nested lookup's connection error under -EnableException and returns nothing, as the forwarded switch does" -Tag NativeChecklist:enable-exception {
            $strictRows = New-Object System.Collections.Generic.List[object]
            $strictCaught = $null
            try {
                Get-DbaAgListener -SqlInstance $hadrInstance, $missingHost -AvailabilityGroup $agNameA -EnableException | ForEach-Object { $strictRows.Add($PSItem) }
            } catch {
                $strictCaught = $PSItem
            }
            $strictRows.Count | Should -Be 0
            $strictCaught | Should -Not -BeNullOrEmpty
            $strictCaught.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
            $strictCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaAvailabilityGroup*"
        }
    }

    Context "Neither an instance nor an input object" -Tag NativeChecklist:enable-exception {
        It "warns and returns nothing" {
            $results = Get-DbaAgListener -WarningVariable noInputWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$noInputWarnings" | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
        }

        It "throws under -EnableException" {
            { Get-DbaAgListener -EnableException } | Should -Throw "*You must supply either -SqlInstance or an Input Object*"
        }

        It "only warns for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            { $null = Get-DbaAgListener -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue } | Should -Not -Throw
            $results = Get-DbaAgListener -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$falseWarnings" | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $sqlLoginCred = $TestConfig.SqlLoginCred
            $missingAgName = "dbatoolsci_aglsn_missing_$random"
        }

        # The missing-credential assertions follow the pinned code quoted below instead of a -Baseline run
        # (watchman 49f13ebb): no commit can run the pinned function, because the base already ships the
        # compiled Get-DbaAgListener cmdlet and the pin predates src/ and cannot be built.
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAgListener.ps1:100-102 (the nested call forwards -EnableException)
        #         if ($SqlInstance) {
        #             $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup -EnableException:$EnableException
        #         }
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAvailabilityGroup.ps1:118-126
        #         foreach ($instance in $SqlInstance) {
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        #
        #             if (-not $server.IsHadrEnabled) {
        #                 Stop-Function -Message "Availability Group (HADR) is not configured for the instance: $instance." -Target $instance -Continue
        #
        # Without the credential the nested connect fails and its Stop-Function -Continue warns "Failure" and moves
        # on. Under -EnableException the forwarded switch makes that Stop-Function throw the ConnectionError record,
        # and nothing in Get-DbaAgListener catches it.
        It "works with -SqlCredential" {
            $results = Get-DbaAgListener -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -AvailabilityGroup $missingAgName -WarningVariable loginWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$loginWarnings" | Should -Not -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $results = Get-DbaAgListener -SqlInstance $loginInstance -AvailabilityGroup $missingAgName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            "$noLoginWarnings" | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException: the forwarded switch throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaAgListener -SqlInstance $loginInstance -AvailabilityGroup $missingAgName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
        }
    }
}

# harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5, and "The -ErrorVariable entry of a
# native -EnableException stop (operator, 2026-11-06)", point 5: the port's complete -ErrorVariable and $Error sequences,
# entry by entry, at the command's two Stop-Function sites, in each call mode. The pin cannot be loaded on a leg, so the
# records are compared with the pin's measured by probe errvar-pin-port-20261117 (items/Get-DbaAgListener/evidence/
# probe-run-errvar-pin-port-20261117-20261117022046.txt, both editions); pin and port per mode are side by side in the
# item notes (point 6).
Describe "Native Get-DbaAgListener error records" -Tag IntegrationTests {
    BeforeAll {
        $recordHost = "dbatoolsci-nohost-$(Get-Random)"
        $listenerThrownSuffix = ",Dataplat.Dbatools.Commands.GetDbaAgListenerCommand"
        $noInputMessage = "You must supply either -SqlInstance or an Input Object"

        # A Pester It runs its body inside a try, so each call runs in a runspace of its own: outside any try, or inside the
        # caller's try with -CallerTry. Returns the output, the error stream, the warnings, the -ErrorVariable and $Error
        # entries (the runspace's own, newest first), the caught record and whether the next statement ran.
        function Invoke-NativeListenerCall {
            param([hashtable]$Arguments, [switch]$CallerTry)
            $callState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $callType = (Get-Command Get-DbaAgListener -CommandType Cmdlet).ImplementingType
            $callEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaAgListener", $callType, $null
            $callState.Commands.Add($callEntry)
            $callRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($callState)
            $callShell = [System.Management.Automation.PowerShell]::Create()
            $callOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $callStop = $null
            $callScript = @'
param($Arguments, $CallerTry)
$global:listenerErrors = @()
$global:listenerWarnings = @()
$global:listenerCaught = $null
if ($CallerTry) {
    try {
        Get-DbaAgListener @Arguments -ErrorVariable listenerErrors -WarningVariable listenerWarnings -WarningAction SilentlyContinue
        "next statement"
    } catch {
        $global:listenerCaught = $PSItem
    }
} else {
    Get-DbaAgListener @Arguments -ErrorVariable listenerErrors -WarningVariable listenerWarnings -WarningAction SilentlyContinue
    "next statement"
}
'@
            try {
                $callRunspace.Open()
                $callShell.Runspace = $callRunspace
                $null = $callShell.AddScript($callScript).AddArgument($Arguments).AddArgument([bool]$CallerTry)
                try {
                    $null = $callShell.Invoke($null, $callOutput)
                } catch {
                    $callStop = $PSItem.Exception
                }
                $streamErrors = @($callShell.Streams.Error)
                $reader = [System.Management.Automation.PowerShell]::Create()
                $reader.Runspace = $callRunspace
                $variableEntries = @($reader.AddScript('$global:listenerErrors').Invoke())
                $reader.Commands.Clear()
                $warningEntries = @($reader.AddScript('$global:listenerWarnings').Invoke())
                $reader.Commands.Clear()
                $caughtEntries = @($reader.AddScript('$global:listenerCaught').Invoke())
                $reader.Commands.Clear()
                $historyEntries = @($reader.AddScript('$global:Error').Invoke())
                $reader.Dispose()
                [pscustomobject]@{
                    Output   = @($callOutput | Where-Object { $PSItem.PSObject.BaseObject -isnot [string] })
                    Text     = @($callOutput | Where-Object { $PSItem.PSObject.BaseObject -is [string] })
                    Errors   = $streamErrors
                    Warnings = @($warningEntries | ForEach-Object { "$PSItem" })
                    Variable = @($variableEntries | ForEach-Object { $PSItem.PSObject.BaseObject })
                    History  = @($historyEntries | ForEach-Object { $PSItem.PSObject.BaseObject })
                    Caught   = @($caughtEntries | Where-Object { $null -ne $PSItem } | ForEach-Object { $PSItem.PSObject.BaseObject })
                    Stop     = $callStop
                }
            } finally {
                $callShell.Dispose()
                $callRunspace.Dispose()
            }
        }

        function Get-NativeEntryText($entries) {
            @($entries | ForEach-Object { "$($PSItem.GetType().Name):$(if ($PSItem -is [System.Management.Automation.ErrorRecord]) { $PSItem.FullyQualifiedErrorId } else { $PSItem.ErrorRecord.FullyQualifiedErrorId })" }) -join " | "
        }

        # The command's own Stop-Function record (pin: the same exception, category, reason and target; its plain record's
        # id carries ",Stop-Function" and Activity "Write-Error", point 4).
        function Assert-NativeNoInputRecord($record, $id) {
            $record | Should -BeOfType System.Management.Automation.ErrorRecord
            $record.FullyQualifiedErrorId | Should -BeExactly $id
            "$($record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $record.CategoryInfo.Reason | Should -BeExactly "Exception"
            $record.CategoryInfo.TargetName | Should -BeExactly ""
            $record.TargetObject | Should -BeNullOrEmpty
            $record.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $record.Exception.Message | Should -BeExactly $noInputMessage
            $record.Exception.InnerException | Should -BeNullOrEmpty
        }

        # The nested lookup's Stop-Function "Failure" record over the failed connect. Pin: the cause itself (the innermost
        # message) with the SqlException beneath it and its Win32Exception beneath that; no "Error connecting to" text.
        function Assert-NativeLookupRecord($record, $id) {
            $record | Should -BeOfType System.Management.Automation.ErrorRecord
            $record.FullyQualifiedErrorId | Should -BeExactly $id
            "$($record.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            $record.CategoryInfo.Reason | Should -BeExactly "Exception"
            $record.CategoryInfo.TargetName | Should -BeExactly $recordHost
            $record.CategoryInfo.TargetType | Should -BeExactly "String"
            "$($record.TargetObject)" | Should -BeExactly $recordHost
            $record.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $cause = $record.Exception.GetBaseException().Message
            $cause | Should -Not -BeNullOrEmpty
            $record.Exception.Message | Should -BeExactly $cause
            $record.Exception.InnerException.GetType().Name | Should -BeExactly "SqlException"
            $record.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly "System.ComponentModel.Win32Exception"
            "$($record.Exception.InnerException)" | Should -Not -BeLike "*Error connecting to*"
        }

        # The record the absorbed Connect-DbaInstance threw into the nested lookup's catch, which the pin keeps in $Error and
        # -ErrorVariable ahead of the lookup's own: its cause after "Error connecting to [<instance>]: ", the same chain beneath.
        function Assert-NativeConnectRecord($record, $cause) {
            $record | Should -BeOfType System.Management.Automation.ErrorRecord
            $record.FullyQualifiedErrorId | Should -BeExactly "dbatools_Connect-DbaInstance"
            "$($record.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            $record.CategoryInfo.Reason | Should -BeExactly "Exception"
            $record.CategoryInfo.TargetName | Should -BeExactly $recordHost
            $record.CategoryInfo.TargetType | Should -BeExactly "String"
            "$($record.TargetObject)" | Should -BeExactly $recordHost
            $record.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $record.Exception.Message | Should -BeExactly "Error connecting to [$recordHost]: $cause"
            $record.Exception.InnerException.GetType().Name | Should -BeExactly "SqlException"
            $record.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly "System.ComponentModel.Win32Exception"
            $record.Exception.GetBaseException().Message | Should -BeExactly $cause
        }

        # The pin's two warning lines, in its order, under -EnableException too (Streams.Warning is not read).
        function Assert-NativeConnectWarnings($warnings, $cause) {
            @($warnings).Count | Should -Be 2 -Because ($warnings -join " | ")
            $warnings[0] | Should -Match ('^(\[[^\]]*\])?\[Connect-DbaInstance\] Failure \| Error connecting to \[' + [regex]::Escape($recordHost) + '\]: ' + [regex]::Escape($cause) + '$')
            $warnings[1] | Should -Match ('^(\[[^\]]*\])?\[Get-DbaAvailabilityGroup\] Failure \| ' + [regex]::Escape($cause) + '$')
        }
    }

    Context "Neither an instance nor an input object" {
        It "keeps the command's one record in -ErrorVariable and `$Error and goes on, <Label>" -ForEach @(
            @{ Label = "plain"; Arguments = @{ }; CallerTry = $false }
            @{ Label = "-ErrorAction SilentlyContinue"; Arguments = @{ ErrorAction = "SilentlyContinue" }; CallerTry = $false }
            @{ Label = "-ErrorAction Stop"; Arguments = @{ ErrorAction = "Stop" }; CallerTry = $false }
            @{ Label = "in a caller's try"; Arguments = @{ }; CallerTry = $true }
        ) {
            $call = Invoke-NativeListenerCall -Arguments $Arguments -CallerTry:$CallerTry
            $call.Stop | Should -BeNullOrEmpty
            $call.Caught.Count | Should -Be 0
            ($call.Text -join ",") | Should -BeExactly "next statement"
            $call.Output.Count | Should -Be 0
            $call.Errors.Count | Should -Be 0
            @($call.Warnings).Count | Should -Be 1
            $call.Warnings[0] | Should -Match ('^(\[[^\]]*\])?\[Get-DbaAgListener\] ' + [regex]::Escape($noInputMessage) + '$')
            $call.Variable.Count | Should -Be 1 -Because (Get-NativeEntryText $call.Variable)
            $call.History.Count | Should -Be 1 -Because (Get-NativeEntryText $call.History)
            Assert-NativeNoInputRecord $call.Variable[0] "dbatools_Get-DbaAgListener"
            [object]::ReferenceEquals($call.Variable[0], $call.History[0]) | Should -BeTrue
        }

        It "stops under -EnableException outside any try: one CmdletInvocationException in -ErrorVariable around the record" -Tag NativeChecklist:enable-exception {
            $call = Invoke-NativeListenerCall -Arguments @{ EnableException = $true }
            # A compiled cmdlet's ThrowTerminatingError ends its statement, where the pin's script throw ends the script
            # (keep-going decision, point 1: outside it, as the installed rules have it).
            $call.Stop | Should -BeNullOrEmpty
            ($call.Text -join ",") | Should -BeExactly "next statement"
            $call.Output.Count | Should -Be 0
            $call.Errors.Count | Should -Be 1
            Assert-NativeNoInputRecord $call.Errors[0] ("dbatools_Get-DbaAgListener" + $listenerThrownSuffix)
            @($call.Warnings).Count | Should -Be 1
            $call.Variable.Count | Should -Be 1 -Because (Get-NativeEntryText $call.Variable)
            $call.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeNoInputRecord $call.Variable[0].ErrorRecord ("dbatools_Get-DbaAgListener" + $listenerThrownSuffix)
            $call.History.Count | Should -Be 1 -Because (Get-NativeEntryText $call.History)
            Assert-NativeNoInputRecord $call.History[0] ("dbatools_Get-DbaAgListener" + $listenerThrownSuffix)
        }

        It "lets a caller's try catch the record under -EnableException" -Tag NativeChecklist:enable-exception {
            $call = Invoke-NativeListenerCall -Arguments @{ EnableException = $true } -CallerTry
            $call.Stop | Should -BeNullOrEmpty
            $call.Text.Count | Should -Be 0
            $call.Caught.Count | Should -Be 1
            Assert-NativeNoInputRecord $call.Caught[0] ("dbatools_Get-DbaAgListener" + $listenerThrownSuffix)
            $call.Variable.Count | Should -Be 1 -Because (Get-NativeEntryText $call.Variable)
            $call.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeNoInputRecord $call.Variable[0].ErrorRecord ("dbatools_Get-DbaAgListener" + $listenerThrownSuffix)
            $call.History.Count | Should -Be 1 -Because (Get-NativeEntryText $call.History)
            Assert-NativeNoInputRecord $call.History[0] ("dbatools_Get-DbaAgListener" + $listenerThrownSuffix)
        }
    }

    Context "An instance that cannot be reached" {
        It "keeps the nested Connect-DbaInstance record, then the lookup's, and goes on, <Label>" -ForEach @(
            @{ Label = "plain"; Arguments = @{ }; CallerTry = $false }
            @{ Label = "-ErrorAction SilentlyContinue"; Arguments = @{ ErrorAction = "SilentlyContinue" }; CallerTry = $false }
            @{ Label = "-ErrorAction Stop"; Arguments = @{ ErrorAction = "Stop" }; CallerTry = $false }
            @{ Label = "in a caller's try"; Arguments = @{ }; CallerTry = $true }
        ) {
            $Arguments.SqlInstance = $recordHost
            $call = Invoke-NativeListenerCall -Arguments $Arguments -CallerTry:$CallerTry
            $call.Stop | Should -BeNullOrEmpty
            $call.Caught.Count | Should -Be 0
            ($call.Text -join ",") | Should -BeExactly "next statement"
            $call.Output.Count | Should -Be 0
            $call.Errors.Count | Should -Be 0
            $call.Variable.Count | Should -Be 2 -Because (Get-NativeEntryText $call.Variable)
            $call.History.Count | Should -Be 2 -Because (Get-NativeEntryText $call.History)
            Assert-NativeLookupRecord $call.Variable[1] "dbatools_Get-DbaAvailabilityGroup"
            $cause = $call.Variable[1].Exception.Message
            Assert-NativeConnectRecord $call.Variable[0] $cause
            [object]::ReferenceEquals($call.History[0], $call.Variable[1]) | Should -BeTrue
            [object]::ReferenceEquals($call.History[1], $call.Variable[0]) | Should -BeTrue
            Assert-NativeConnectWarnings $call.Warnings $cause
        }

        It "stops under -EnableException outside any try: the Connect-DbaInstance record, then one CmdletInvocationException" -Tag NativeChecklist:enable-exception {
            $call = Invoke-NativeListenerCall -Arguments @{ SqlInstance = $recordHost; EnableException = $true }
            $call.Stop | Should -BeNullOrEmpty
            ($call.Text -join ",") | Should -BeExactly "next statement"
            $call.Output.Count | Should -Be 0
            $call.Errors.Count | Should -Be 1
            Assert-NativeLookupRecord $call.Errors[0] ("dbatools_Get-DbaAvailabilityGroup" + $listenerThrownSuffix)
            $cause = $call.Errors[0].Exception.Message
            $call.Variable.Count | Should -Be 2 -Because (Get-NativeEntryText $call.Variable)
            Assert-NativeConnectRecord $call.Variable[0] $cause
            $call.Variable[1].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeLookupRecord $call.Variable[1].ErrorRecord ("dbatools_Get-DbaAvailabilityGroup" + $listenerThrownSuffix)
            $call.History.Count | Should -Be 2 -Because (Get-NativeEntryText $call.History)
            Assert-NativeLookupRecord $call.History[0] ("dbatools_Get-DbaAvailabilityGroup" + $listenerThrownSuffix)
            [object]::ReferenceEquals($call.History[1], $call.Variable[0]) | Should -BeTrue
            Assert-NativeConnectWarnings $call.Warnings $cause
        }

        It "lets a caller's try catch the lookup's record under -EnableException" -Tag NativeChecklist:enable-exception {
            $call = Invoke-NativeListenerCall -Arguments @{ SqlInstance = $recordHost; EnableException = $true } -CallerTry
            $call.Stop | Should -BeNullOrEmpty
            $call.Text.Count | Should -Be 0
            $call.Output.Count | Should -Be 0
            $call.Caught.Count | Should -Be 1
            Assert-NativeLookupRecord $call.Caught[0] ("dbatools_Get-DbaAvailabilityGroup" + $listenerThrownSuffix)
            $cause = $call.Caught[0].Exception.Message
            $call.Variable.Count | Should -Be 2 -Because (Get-NativeEntryText $call.Variable)
            Assert-NativeConnectRecord $call.Variable[0] $cause
            $call.Variable[1].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeLookupRecord $call.Variable[1].ErrorRecord ("dbatools_Get-DbaAvailabilityGroup" + $listenerThrownSuffix)
            $call.History.Count | Should -Be 2 -Because (Get-NativeEntryText $call.History)
            Assert-NativeLookupRecord $call.History[0] ("dbatools_Get-DbaAvailabilityGroup" + $listenerThrownSuffix)
            [object]::ReferenceEquals($call.History[1], $call.Variable[0]) | Should -BeTrue
            Assert-NativeConnectWarnings $call.Warnings $cause
        }
    }
}

Describe "Native Get-DbaAgListener refuses Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per test.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
    }

    It "warns that Azure SQL Database is not supported and returns nothing" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
        }
        @(Get-DbaAgListener @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "throws a connection error for Azure SQL Database under -EnableException, as the forwarded switch does" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureCaught = $null
        try {
            $null = Get-DbaAgListener -SqlInstance $azureServer -EnableException
        } catch {
            $azureCaught = $PSItem
        }
        $azureCaught | Should -Not -BeNullOrEmpty
        $azureCaught.CategoryInfo.Category.ToString() | Should -Be "ConnectionError"
        $azureCaught.Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }
}
