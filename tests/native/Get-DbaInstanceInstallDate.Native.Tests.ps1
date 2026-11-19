#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- the pinned command does not declare SupportsShouldProcess, so it has no -WhatIf or -Confirm.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaInstanceInstallDate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaInstanceInstallDate" -Tag IntegrationTests {
    BeforeAll {
        $installServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $installMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $installNetBios = $installServer.ComputerNamePhysicalNetBIOS

        # Independent reads: the creation date of the NT AUTHORITY\SYSTEM login on the test's own connection, and the
        # operating system's InstallDate over CIM.
        $installSqlDate = [datetime]($installServer.ConnectionContext.ExecuteScalar("SELECT create_date FROM sys.server_principals WHERE sid = 0x010100000000000512000000"))
        $installOsDate = (Get-CimInstance -ComputerName $installNetBios -ClassName Win32_OperatingSystem -ErrorAction Stop).InstallDate
    }

    It "returns the install date of the instance with the four default properties" {
        $installErrors = @()
        $results = @(Get-DbaInstanceInstallDate -SqlInstance $TestConfig.InstanceSingle -ErrorVariable installErrors)
        $installErrors | Should -BeNullOrEmpty
        $results.Count | Should -Be 1
        $result = $results[0]
        $result.ComputerName | Should -BeExactly $installServer.ComputerName
        $result.InstanceName | Should -BeExactly $installServer.ServiceName
        $result.SqlInstance | Should -BeExactly $installServer.DomainInstanceName
        $result.SqlInstallDate | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
        ([datetime]$result.SqlInstallDate) | Should -Be $installSqlDate
        $result.WindowsInstallDate | Should -BeNullOrEmpty
        @($result.PSObject.Properties.Name) -join "," | Should -BeExactly "ComputerName,InstanceName,SqlInstance,SqlInstallDate,WindowsInstallDate"
        $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join "," | Should -BeExactly "ComputerName,InstanceName,SqlInstance,SqlInstallDate"
    }

    It "adds the Windows install date with -IncludeWindows" {
        $result = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.InstanceSingle -IncludeWindows -EnableException
        $result.WindowsInstallDate | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
        ([datetime]$result.WindowsInstallDate) | Should -Be $installOsDate
        ([datetime]$result.SqlInstallDate) | Should -Be $installSqlDate
        $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join "," | Should -BeExactly "ComputerName,InstanceName,SqlInstance,SqlInstallDate,WindowsInstallDate"
    }

    It "returns no date of the Windows install with -IncludeWindows:`$false" -Tag "NativeChecklist:switch-false" {
        $result = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.InstanceSingle -IncludeWindows:$false -EnableException:$false
        $result.WindowsInstallDate | Should -BeNullOrEmpty
        $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join "," | Should -BeExactly "ComputerName,InstanceName,SqlInstance,SqlInstallDate"
    }

    It "returns the date of each piped instance and goes on past one that fails" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure" {
        $warnings = @()
        $results = @(@($TestConfig.InstanceSingle, $installMissing, $TestConfig.InstanceSingle) | Get-DbaInstanceInstallDate -WarningAction SilentlyContinue -WarningVariable warnings)
        $results.Count | Should -Be 2
        foreach ($result in $results) {
            ([datetime]$result.SqlInstallDate) | Should -Be $installSqlDate
        }
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaInstanceInstallDate] Failure | Error connecting to [$installMissing]: "))
    }

    It "throws the connection failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
        { Get-DbaInstanceInstallDate -SqlInstance $installMissing -EnableException -WarningAction SilentlyContinue } | Should -Throw
    }

    Context "a Windows read that fails" {
        BeforeAll {
            # A credential the target's management connection already knows to be bad: Get-DbaCmObject refuses it before
            # it contacts the computer. The connection cache entry is put back afterwards.
            $installKey = $installNetBios.ToLowerInvariant()
            $installSaved = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$installKey]
            $installBadUser = "nativenobody" + [guid]::NewGuid().ToString("N").Substring(0, 12)
            $installBadPassword = ConvertTo-SecureString ("NotThePassword" + [guid]::NewGuid().ToString("N")) -AsPlainText -Force
            $installBadCredential = New-Object System.Management.Automation.PSCredential($installBadUser, $installBadPassword)
            $installConnection = New-Object Dataplat.Dbatools.Connection.ManagementConnection -ArgumentList $installKey
            $installConnection.AddBadCredential($installBadCredential)
            [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$installKey] = $installConnection

            # The record the pinned catch gives on this leg, for the -EnableException stop (harness-edits.md, "The -ErrorVariable
            # entry of a native -EnableException stop", point 5). The pin catches what Get-DbaCmObject -EnableException throws
            # and passes it on:
            #     Stop-Function -Message "Failed to connect to: $WindowsServerName" -Continue -Target $instance -ErrorRecord $_
            # which under -EnableException throws the record it builds. Both calls run here as the pin makes them, in the module's
            # scope, where Stop-Function builds its record as the pinned one does (private/functions/flowcontrol/Stop-Function.ps1).
            function Get-NativePinnedStop {
                $dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
                $pinnedTarget = [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$TestConfig.InstanceSingle
                & $dbatoolsModule {
                    param($NetBios, $BadCredential, $StopTarget)
                    $EnableException = $true
                    try {
                        $null = Get-DbaCmObject -ClassName win32_OperatingSystem -ComputerName $NetBios -Credential $BadCredential -EnableException -WarningAction SilentlyContinue
                    } catch {
                        $nestedRecord = $PSItem
                        try {
                            Stop-Function -Message "Failed to connect to: $NetBios" -Continue -Target $StopTarget -ErrorRecord $nestedRecord -FunctionName "Get-DbaInstanceInstallDate" 3>$null
                        } catch {
                            return $PSItem
                        }
                    }
                } $installNetBios $installBadCredential $pinnedTarget
            }

            # Point 2's content comparison. The id is the pinned one with the engine's suffix of this command's implementing
            # type, as installed section 4 ("Own-command error attribution") allows where the pin has no suffix.
            function Assert-NativePinnedStop {
                param($Record, $Pinned)
                $implementing = (Get-Command -Name Get-DbaInstanceInstallDate -CommandType Cmdlet).ImplementingType.FullName
                $Pinned | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $Record.FullyQualifiedErrorId | Should -BeExactly ($Pinned.FullyQualifiedErrorId + "," + $implementing)
                $Record.Exception.GetType().FullName | Should -BeExactly $Pinned.Exception.GetType().FullName
                $Record.Exception.Message | Should -BeExactly $Pinned.Exception.Message
                $Record.CategoryInfo.Category | Should -Be $Pinned.CategoryInfo.Category
                $Record.CategoryInfo.Reason | Should -BeExactly $Pinned.CategoryInfo.Reason
                $Record.CategoryInfo.TargetName | Should -BeExactly $Pinned.CategoryInfo.TargetName
                $Record.CategoryInfo.TargetType | Should -BeExactly $Pinned.CategoryInfo.TargetType
                $Record.TargetObject.GetType().FullName | Should -BeExactly $Pinned.TargetObject.GetType().FullName
                "$($Record.TargetObject)" | Should -BeExactly "$($Pinned.TargetObject)"
                $inner = $Record.Exception.InnerException
                $pinnedInner = $Pinned.Exception.InnerException
                $pinnedInner | Should -Not -BeNullOrEmpty
                while ($null -ne $pinnedInner -or $null -ne $inner) {
                    $inner | Should -Not -BeNullOrEmpty
                    $pinnedInner | Should -Not -BeNullOrEmpty
                    $inner.GetType().FullName | Should -BeExactly $pinnedInner.GetType().FullName
                    $inner.Message | Should -BeExactly $pinnedInner.Message
                    $inner = $inner.InnerException
                    $pinnedInner = $pinnedInner.InnerException
                }
            }
        }

        AfterAll {
            if ($installSaved) {
                [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$installKey] = $installSaved
            } else {
                $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($installKey)
            }
        }

        It "warns that it failed to connect, gives no object for that instance and goes on" {
            $warnings = @()
            $results = @(Get-DbaInstanceInstallDate -SqlInstance $TestConfig.InstanceSingle, $TestConfig.InstanceSingle -IncludeWindows -Credential $installBadCredential -WarningAction SilentlyContinue -WarningVariable warnings)
            $results.Count | Should -Be 0
            @($warnings | Where-Object { "$PSItem" -like "*Failed to connect to: $installNetBios*" }).Count | Should -Be 2
        }

        # The pinned Stop-Function throws a record whose message is the innermost message of the caught record (Get-ErrorMessage),
        # here the known-bad credential's refusal; "Failed to connect to" is only the warning's text.
        It "throws it under -EnableException" {
            $caught = $null
            try {
                $null = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.InstanceSingle -IncludeWindows -Credential $installBadCredential -EnableException -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            $caught.Exception.Message | Should -BeExactly "Specified credentials failed"
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaInstanceInstallDate*"
        }

        # The pinned catch catches the record the nested Get-DbaCmObject -EnableException throws. The engine puts that record in
        # the caller's -ErrorVariable as well as in $Error, ahead of the command's own Stop-Function record, for each instance, in
        # every call mode and on both editions (pin probe d4f2db87, evidence/pin-errvar-badcred-20261106.txt). The pin's variable
        # also holds the record of the GetCredential call the nested function caught, a call the port does not make, and the
        # engine's unwind copies, RuntimeException and ContinueException entries (accepted difference
        # omitted-consequential-records): the port's -ErrorVariable holds exactly the distinct records it puts in $Error, once
        # each, in the order they were written (manager 1288e19ad99f, watchman 29bfcc11).
        It "holds in -ErrorVariable each nested Get-DbaCmObject record and its own record once, as in Error (plain, 1 instances)" -ForEach @(
            @{ Mode = "plain"; Count = 1 }
        ) {
            $splatBadWindows = @{
                SqlInstance    = @(1..$Count | ForEach-Object { $TestConfig.InstanceSingle })
                IncludeWindows = $true
                Credential     = $installBadCredential
                WarningAction  = "SilentlyContinue"
                ErrorVariable  = "installErrors"
            }
            $installErrors = $null
            $caught = $null
            $reached = $false
            $results = @()
            # Measured before $Error is cleared, so its own records are not counted below.
            $pinnedStop = if ($Mode -eq "EnableException") { Get-NativePinnedStop } else { $null }
            $global:Error.Clear()
            if ($Mode -eq "plain") {
                $results = @(Get-DbaInstanceInstallDate @splatBadWindows)
                $reached = $true
            } else {
                try {
                    if ($Mode -eq "EnableException") {
                        $results = @(Get-DbaInstanceInstallDate @splatBadWindows -EnableException)
                    } else {
                        $results = @(Get-DbaInstanceInstallDate @splatBadWindows)
                    }
                    $reached = $true
                } catch {
                    $caught = $PSItem
                }
            }
            $written = @($global:Error)
            [array]::Reverse($written)

            # -EnableException stops at the first instance; the other modes warn and go on to the next.
            $instances = if ($Mode -eq "EnableException") { 1 } else { $Count }
            $results.Count | Should -Be 0
            if ($Mode -eq "EnableException") {
                $caught | Should -Not -BeNullOrEmpty
                Assert-NativePinnedStop -Record $caught -Pinned $pinnedStop
                $reached | Should -BeFalse
            } else {
                $caught | Should -BeNullOrEmpty
                $reached | Should -BeTrue
            }
            $written.Count | Should -Be (2 * $instances)
            for ($i = 0; $i -lt $instances; $i++) {
                $written[2 * $i] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $written[2 * $i].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
                $written[2 * $i].Exception.Message | Should -BeExactly "Specified credentials failed"
                "$($written[2 * $i].TargetObject)" | Should -BeExactly $installNetBios.ToLowerInvariant()
                $written[2 * $i + 1] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $written[2 * $i + 1].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaInstanceInstallDate*"
                $written[2 * $i + 1].Exception.Message | Should -BeExactly "Specified credentials failed"
            }
            for ($i = 0; $i -lt $written.Count; $i++) {
                for ($j = 0; $j -lt $i; $j++) {
                    [object]::ReferenceEquals($written[$i], $written[$j]) | Should -BeFalse
                }
            }
            # The stop's record is the last one $Error gains, and the stop's -ErrorVariable entry is the last one there: the
            # engine's CmdletInvocationException, whose .ErrorRecord equals the pinned record by content (harness-edits.md,
            # "The -ErrorVariable entry of a native -EnableException stop", points 2 and 5; the pin leaves the bare record).
            if ($Mode -eq "EnableException") {
                Assert-NativePinnedStop -Record $written[-1] -Pinned $pinnedStop
                $stopEntry = @($installErrors)[-1]
                $stopEntry | Should -BeOfType [System.Management.Automation.CmdletInvocationException]
                Assert-NativePinnedStop -Record $stopEntry.ErrorRecord -Pinned $pinnedStop
            }

            # -ErrorVariable: exactly those records, in that order, no copy and nothing else; under -EnableException the stop
            # adds exactly one entry, the one compared above.
            @($installErrors).Count | Should -Be $written.Count
            for ($i = 0; $i -lt $written.Count; $i++) {
                for ($j = 0; $j -lt $i; $j++) {
                    [object]::ReferenceEquals($installErrors[$i], $installErrors[$j]) | Should -BeFalse -Because "entry $i of -ErrorVariable is not entry $j again"
                }
                if ($Mode -eq "EnableException" -and $i -eq ($written.Count - 1)) {
                    [object]::ReferenceEquals($installErrors[$i], $stopEntry) | Should -BeTrue -Because "the last entry is the stop's"
                } else {
                    [object]::ReferenceEquals($installErrors[$i], $written[$i]) | Should -BeTrue -Because "entry $i of -ErrorVariable is the record written $i"
                }
            }
        }

        It "holds in -ErrorVariable each nested Get-DbaCmObject record and its own record once, as in Error (plain, 2 instances)" -ForEach @(
            @{ Mode = "plain"; Count = 2 }
        ) {
            $splatBadWindows = @{
                SqlInstance    = @(1..$Count | ForEach-Object { $TestConfig.InstanceSingle })
                IncludeWindows = $true
                Credential     = $installBadCredential
                WarningAction  = "SilentlyContinue"
                ErrorVariable  = "installErrors"
            }
            $installErrors = $null
            $caught = $null
            $reached = $false
            $results = @()
            # Measured before $Error is cleared, so its own records are not counted below.
            $pinnedStop = if ($Mode -eq "EnableException") { Get-NativePinnedStop } else { $null }
            $global:Error.Clear()
            if ($Mode -eq "plain") {
                $results = @(Get-DbaInstanceInstallDate @splatBadWindows)
                $reached = $true
            } else {
                try {
                    if ($Mode -eq "EnableException") {
                        $results = @(Get-DbaInstanceInstallDate @splatBadWindows -EnableException)
                    } else {
                        $results = @(Get-DbaInstanceInstallDate @splatBadWindows)
                    }
                    $reached = $true
                } catch {
                    $caught = $PSItem
                }
            }
            $written = @($global:Error)
            [array]::Reverse($written)

            # -EnableException stops at the first instance; the other modes warn and go on to the next.
            $instances = if ($Mode -eq "EnableException") { 1 } else { $Count }
            $results.Count | Should -Be 0
            if ($Mode -eq "EnableException") {
                $caught | Should -Not -BeNullOrEmpty
                Assert-NativePinnedStop -Record $caught -Pinned $pinnedStop
                $reached | Should -BeFalse
            } else {
                $caught | Should -BeNullOrEmpty
                $reached | Should -BeTrue
            }
            $written.Count | Should -Be (2 * $instances)
            for ($i = 0; $i -lt $instances; $i++) {
                $written[2 * $i] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $written[2 * $i].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
                $written[2 * $i].Exception.Message | Should -BeExactly "Specified credentials failed"
                "$($written[2 * $i].TargetObject)" | Should -BeExactly $installNetBios.ToLowerInvariant()
                $written[2 * $i + 1] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $written[2 * $i + 1].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaInstanceInstallDate*"
                $written[2 * $i + 1].Exception.Message | Should -BeExactly "Specified credentials failed"
            }
            for ($i = 0; $i -lt $written.Count; $i++) {
                for ($j = 0; $j -lt $i; $j++) {
                    [object]::ReferenceEquals($written[$i], $written[$j]) | Should -BeFalse
                }
            }
            # The stop's record is the last one $Error gains, and the stop's -ErrorVariable entry is the last one there: the
            # engine's CmdletInvocationException, whose .ErrorRecord equals the pinned record by content (harness-edits.md,
            # "The -ErrorVariable entry of a native -EnableException stop", points 2 and 5; the pin leaves the bare record).
            if ($Mode -eq "EnableException") {
                Assert-NativePinnedStop -Record $written[-1] -Pinned $pinnedStop
                $stopEntry = @($installErrors)[-1]
                $stopEntry | Should -BeOfType [System.Management.Automation.CmdletInvocationException]
                Assert-NativePinnedStop -Record $stopEntry.ErrorRecord -Pinned $pinnedStop
            }

            # -ErrorVariable: exactly those records, in that order, no copy and nothing else; under -EnableException the stop
            # adds exactly one entry, the one compared above.
            @($installErrors).Count | Should -Be $written.Count
            for ($i = 0; $i -lt $written.Count; $i++) {
                for ($j = 0; $j -lt $i; $j++) {
                    [object]::ReferenceEquals($installErrors[$i], $installErrors[$j]) | Should -BeFalse -Because "entry $i of -ErrorVariable is not entry $j again"
                }
                if ($Mode -eq "EnableException" -and $i -eq ($written.Count - 1)) {
                    [object]::ReferenceEquals($installErrors[$i], $stopEntry) | Should -BeTrue -Because "the last entry is the stop's"
                } else {
                    [object]::ReferenceEquals($installErrors[$i], $written[$i]) | Should -BeTrue -Because "entry $i of -ErrorVariable is the record written $i"
                }
            }
        }

        It "holds in -ErrorVariable each nested Get-DbaCmObject record and its own record once, as in Error (caller try, 1 instances)" -ForEach @(
            @{ Mode = "caller try"; Count = 1 }
        ) {
            $splatBadWindows = @{
                SqlInstance    = @(1..$Count | ForEach-Object { $TestConfig.InstanceSingle })
                IncludeWindows = $true
                Credential     = $installBadCredential
                WarningAction  = "SilentlyContinue"
                ErrorVariable  = "installErrors"
            }
            $installErrors = $null
            $caught = $null
            $reached = $false
            $results = @()
            # Measured before $Error is cleared, so its own records are not counted below.
            $pinnedStop = if ($Mode -eq "EnableException") { Get-NativePinnedStop } else { $null }
            $global:Error.Clear()
            if ($Mode -eq "plain") {
                $results = @(Get-DbaInstanceInstallDate @splatBadWindows)
                $reached = $true
            } else {
                try {
                    if ($Mode -eq "EnableException") {
                        $results = @(Get-DbaInstanceInstallDate @splatBadWindows -EnableException)
                    } else {
                        $results = @(Get-DbaInstanceInstallDate @splatBadWindows)
                    }
                    $reached = $true
                } catch {
                    $caught = $PSItem
                }
            }
            $written = @($global:Error)
            [array]::Reverse($written)

            # -EnableException stops at the first instance; the other modes warn and go on to the next.
            $instances = if ($Mode -eq "EnableException") { 1 } else { $Count }
            $results.Count | Should -Be 0
            if ($Mode -eq "EnableException") {
                $caught | Should -Not -BeNullOrEmpty
                Assert-NativePinnedStop -Record $caught -Pinned $pinnedStop
                $reached | Should -BeFalse
            } else {
                $caught | Should -BeNullOrEmpty
                $reached | Should -BeTrue
            }
            $written.Count | Should -Be (2 * $instances)
            for ($i = 0; $i -lt $instances; $i++) {
                $written[2 * $i] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $written[2 * $i].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
                $written[2 * $i].Exception.Message | Should -BeExactly "Specified credentials failed"
                "$($written[2 * $i].TargetObject)" | Should -BeExactly $installNetBios.ToLowerInvariant()
                $written[2 * $i + 1] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $written[2 * $i + 1].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaInstanceInstallDate*"
                $written[2 * $i + 1].Exception.Message | Should -BeExactly "Specified credentials failed"
            }
            for ($i = 0; $i -lt $written.Count; $i++) {
                for ($j = 0; $j -lt $i; $j++) {
                    [object]::ReferenceEquals($written[$i], $written[$j]) | Should -BeFalse
                }
            }
            # The stop's record is the last one $Error gains, and the stop's -ErrorVariable entry is the last one there: the
            # engine's CmdletInvocationException, whose .ErrorRecord equals the pinned record by content (harness-edits.md,
            # "The -ErrorVariable entry of a native -EnableException stop", points 2 and 5; the pin leaves the bare record).
            if ($Mode -eq "EnableException") {
                Assert-NativePinnedStop -Record $written[-1] -Pinned $pinnedStop
                $stopEntry = @($installErrors)[-1]
                $stopEntry | Should -BeOfType [System.Management.Automation.CmdletInvocationException]
                Assert-NativePinnedStop -Record $stopEntry.ErrorRecord -Pinned $pinnedStop
            }

            # -ErrorVariable: exactly those records, in that order, no copy and nothing else; under -EnableException the stop
            # adds exactly one entry, the one compared above.
            @($installErrors).Count | Should -Be $written.Count
            for ($i = 0; $i -lt $written.Count; $i++) {
                for ($j = 0; $j -lt $i; $j++) {
                    [object]::ReferenceEquals($installErrors[$i], $installErrors[$j]) | Should -BeFalse -Because "entry $i of -ErrorVariable is not entry $j again"
                }
                if ($Mode -eq "EnableException" -and $i -eq ($written.Count - 1)) {
                    [object]::ReferenceEquals($installErrors[$i], $stopEntry) | Should -BeTrue -Because "the last entry is the stop's"
                } else {
                    [object]::ReferenceEquals($installErrors[$i], $written[$i]) | Should -BeTrue -Because "entry $i of -ErrorVariable is the record written $i"
                }
            }
        }

        It "holds in -ErrorVariable each nested Get-DbaCmObject record and its own record once, as in Error (caller try, 2 instances)" -ForEach @(
            @{ Mode = "caller try"; Count = 2 }
        ) {
            $splatBadWindows = @{
                SqlInstance    = @(1..$Count | ForEach-Object { $TestConfig.InstanceSingle })
                IncludeWindows = $true
                Credential     = $installBadCredential
                WarningAction  = "SilentlyContinue"
                ErrorVariable  = "installErrors"
            }
            $installErrors = $null
            $caught = $null
            $reached = $false
            $results = @()
            # Measured before $Error is cleared, so its own records are not counted below.
            $pinnedStop = if ($Mode -eq "EnableException") { Get-NativePinnedStop } else { $null }
            $global:Error.Clear()
            if ($Mode -eq "plain") {
                $results = @(Get-DbaInstanceInstallDate @splatBadWindows)
                $reached = $true
            } else {
                try {
                    if ($Mode -eq "EnableException") {
                        $results = @(Get-DbaInstanceInstallDate @splatBadWindows -EnableException)
                    } else {
                        $results = @(Get-DbaInstanceInstallDate @splatBadWindows)
                    }
                    $reached = $true
                } catch {
                    $caught = $PSItem
                }
            }
            $written = @($global:Error)
            [array]::Reverse($written)

            # -EnableException stops at the first instance; the other modes warn and go on to the next.
            $instances = if ($Mode -eq "EnableException") { 1 } else { $Count }
            $results.Count | Should -Be 0
            if ($Mode -eq "EnableException") {
                $caught | Should -Not -BeNullOrEmpty
                Assert-NativePinnedStop -Record $caught -Pinned $pinnedStop
                $reached | Should -BeFalse
            } else {
                $caught | Should -BeNullOrEmpty
                $reached | Should -BeTrue
            }
            $written.Count | Should -Be (2 * $instances)
            for ($i = 0; $i -lt $instances; $i++) {
                $written[2 * $i] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $written[2 * $i].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
                $written[2 * $i].Exception.Message | Should -BeExactly "Specified credentials failed"
                "$($written[2 * $i].TargetObject)" | Should -BeExactly $installNetBios.ToLowerInvariant()
                $written[2 * $i + 1] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $written[2 * $i + 1].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaInstanceInstallDate*"
                $written[2 * $i + 1].Exception.Message | Should -BeExactly "Specified credentials failed"
            }
            for ($i = 0; $i -lt $written.Count; $i++) {
                for ($j = 0; $j -lt $i; $j++) {
                    [object]::ReferenceEquals($written[$i], $written[$j]) | Should -BeFalse
                }
            }
            # The stop's record is the last one $Error gains, and the stop's -ErrorVariable entry is the last one there: the
            # engine's CmdletInvocationException, whose .ErrorRecord equals the pinned record by content (harness-edits.md,
            # "The -ErrorVariable entry of a native -EnableException stop", points 2 and 5; the pin leaves the bare record).
            if ($Mode -eq "EnableException") {
                Assert-NativePinnedStop -Record $written[-1] -Pinned $pinnedStop
                $stopEntry = @($installErrors)[-1]
                $stopEntry | Should -BeOfType [System.Management.Automation.CmdletInvocationException]
                Assert-NativePinnedStop -Record $stopEntry.ErrorRecord -Pinned $pinnedStop
            }

            # -ErrorVariable: exactly those records, in that order, no copy and nothing else; under -EnableException the stop
            # adds exactly one entry, the one compared above.
            @($installErrors).Count | Should -Be $written.Count
            for ($i = 0; $i -lt $written.Count; $i++) {
                for ($j = 0; $j -lt $i; $j++) {
                    [object]::ReferenceEquals($installErrors[$i], $installErrors[$j]) | Should -BeFalse -Because "entry $i of -ErrorVariable is not entry $j again"
                }
                if ($Mode -eq "EnableException" -and $i -eq ($written.Count - 1)) {
                    [object]::ReferenceEquals($installErrors[$i], $stopEntry) | Should -BeTrue -Because "the last entry is the stop's"
                } else {
                    [object]::ReferenceEquals($installErrors[$i], $written[$i]) | Should -BeTrue -Because "entry $i of -ErrorVariable is the record written $i"
                }
            }
        }

        It "holds in -ErrorVariable each nested Get-DbaCmObject record and its own record once, as in Error (EnableException, 1 instances)" -ForEach @(
            @{ Mode = "EnableException"; Count = 1 }
        ) {
            $splatBadWindows = @{
                SqlInstance    = @(1..$Count | ForEach-Object { $TestConfig.InstanceSingle })
                IncludeWindows = $true
                Credential     = $installBadCredential
                WarningAction  = "SilentlyContinue"
                ErrorVariable  = "installErrors"
            }
            $installErrors = $null
            $caught = $null
            $reached = $false
            $results = @()
            # Measured before $Error is cleared, so its own records are not counted below.
            $pinnedStop = if ($Mode -eq "EnableException") { Get-NativePinnedStop } else { $null }
            $global:Error.Clear()
            if ($Mode -eq "plain") {
                $results = @(Get-DbaInstanceInstallDate @splatBadWindows)
                $reached = $true
            } else {
                try {
                    if ($Mode -eq "EnableException") {
                        $results = @(Get-DbaInstanceInstallDate @splatBadWindows -EnableException)
                    } else {
                        $results = @(Get-DbaInstanceInstallDate @splatBadWindows)
                    }
                    $reached = $true
                } catch {
                    $caught = $PSItem
                }
            }
            $written = @($global:Error)
            [array]::Reverse($written)

            # -EnableException stops at the first instance; the other modes warn and go on to the next.
            $instances = if ($Mode -eq "EnableException") { 1 } else { $Count }
            $results.Count | Should -Be 0
            if ($Mode -eq "EnableException") {
                $caught | Should -Not -BeNullOrEmpty
                Assert-NativePinnedStop -Record $caught -Pinned $pinnedStop
                $reached | Should -BeFalse
            } else {
                $caught | Should -BeNullOrEmpty
                $reached | Should -BeTrue
            }
            $written.Count | Should -Be (2 * $instances)
            for ($i = 0; $i -lt $instances; $i++) {
                $written[2 * $i] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $written[2 * $i].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
                $written[2 * $i].Exception.Message | Should -BeExactly "Specified credentials failed"
                "$($written[2 * $i].TargetObject)" | Should -BeExactly $installNetBios.ToLowerInvariant()
                $written[2 * $i + 1] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $written[2 * $i + 1].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaInstanceInstallDate*"
                $written[2 * $i + 1].Exception.Message | Should -BeExactly "Specified credentials failed"
            }
            for ($i = 0; $i -lt $written.Count; $i++) {
                for ($j = 0; $j -lt $i; $j++) {
                    [object]::ReferenceEquals($written[$i], $written[$j]) | Should -BeFalse
                }
            }
            # The stop's record is the last one $Error gains, and the stop's -ErrorVariable entry is the last one there: the
            # engine's CmdletInvocationException, whose .ErrorRecord equals the pinned record by content (harness-edits.md,
            # "The -ErrorVariable entry of a native -EnableException stop", points 2 and 5; the pin leaves the bare record).
            if ($Mode -eq "EnableException") {
                Assert-NativePinnedStop -Record $written[-1] -Pinned $pinnedStop
                $stopEntry = @($installErrors)[-1]
                $stopEntry | Should -BeOfType [System.Management.Automation.CmdletInvocationException]
                Assert-NativePinnedStop -Record $stopEntry.ErrorRecord -Pinned $pinnedStop
            }

            # -ErrorVariable: exactly those records, in that order, no copy and nothing else; under -EnableException the stop
            # adds exactly one entry, the one compared above.
            @($installErrors).Count | Should -Be $written.Count
            for ($i = 0; $i -lt $written.Count; $i++) {
                for ($j = 0; $j -lt $i; $j++) {
                    [object]::ReferenceEquals($installErrors[$i], $installErrors[$j]) | Should -BeFalse -Because "entry $i of -ErrorVariable is not entry $j again"
                }
                if ($Mode -eq "EnableException" -and $i -eq ($written.Count - 1)) {
                    [object]::ReferenceEquals($installErrors[$i], $stopEntry) | Should -BeTrue -Because "the last entry is the stop's"
                } else {
                    [object]::ReferenceEquals($installErrors[$i], $written[$i]) | Should -BeTrue -Because "entry $i of -ErrorVariable is the record written $i"
                }
            }
        }

        It "holds in -ErrorVariable each nested Get-DbaCmObject record and its own record once, as in Error (EnableException, 2 instances)" -ForEach @(
            @{ Mode = "EnableException"; Count = 2 }
        ) {
            $splatBadWindows = @{
                SqlInstance    = @(1..$Count | ForEach-Object { $TestConfig.InstanceSingle })
                IncludeWindows = $true
                Credential     = $installBadCredential
                WarningAction  = "SilentlyContinue"
                ErrorVariable  = "installErrors"
            }
            $installErrors = $null
            $caught = $null
            $reached = $false
            $results = @()
            # Measured before $Error is cleared, so its own records are not counted below.
            $pinnedStop = if ($Mode -eq "EnableException") { Get-NativePinnedStop } else { $null }
            $global:Error.Clear()
            if ($Mode -eq "plain") {
                $results = @(Get-DbaInstanceInstallDate @splatBadWindows)
                $reached = $true
            } else {
                try {
                    if ($Mode -eq "EnableException") {
                        $results = @(Get-DbaInstanceInstallDate @splatBadWindows -EnableException)
                    } else {
                        $results = @(Get-DbaInstanceInstallDate @splatBadWindows)
                    }
                    $reached = $true
                } catch {
                    $caught = $PSItem
                }
            }
            $written = @($global:Error)
            [array]::Reverse($written)

            # -EnableException stops at the first instance; the other modes warn and go on to the next.
            $instances = if ($Mode -eq "EnableException") { 1 } else { $Count }
            $results.Count | Should -Be 0
            if ($Mode -eq "EnableException") {
                $caught | Should -Not -BeNullOrEmpty
                Assert-NativePinnedStop -Record $caught -Pinned $pinnedStop
                $reached | Should -BeFalse
            } else {
                $caught | Should -BeNullOrEmpty
                $reached | Should -BeTrue
            }
            $written.Count | Should -Be (2 * $instances)
            for ($i = 0; $i -lt $instances; $i++) {
                $written[2 * $i] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $written[2 * $i].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaCmObject*"
                $written[2 * $i].Exception.Message | Should -BeExactly "Specified credentials failed"
                "$($written[2 * $i].TargetObject)" | Should -BeExactly $installNetBios.ToLowerInvariant()
                $written[2 * $i + 1] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $written[2 * $i + 1].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaInstanceInstallDate*"
                $written[2 * $i + 1].Exception.Message | Should -BeExactly "Specified credentials failed"
            }
            for ($i = 0; $i -lt $written.Count; $i++) {
                for ($j = 0; $j -lt $i; $j++) {
                    [object]::ReferenceEquals($written[$i], $written[$j]) | Should -BeFalse
                }
            }
            # The stop's record is the last one $Error gains, and the stop's -ErrorVariable entry is the last one there: the
            # engine's CmdletInvocationException, whose .ErrorRecord equals the pinned record by content (harness-edits.md,
            # "The -ErrorVariable entry of a native -EnableException stop", points 2 and 5; the pin leaves the bare record).
            if ($Mode -eq "EnableException") {
                Assert-NativePinnedStop -Record $written[-1] -Pinned $pinnedStop
                $stopEntry = @($installErrors)[-1]
                $stopEntry | Should -BeOfType [System.Management.Automation.CmdletInvocationException]
                Assert-NativePinnedStop -Record $stopEntry.ErrorRecord -Pinned $pinnedStop
            }

            # -ErrorVariable: exactly those records, in that order, no copy and nothing else; under -EnableException the stop
            # adds exactly one entry, the one compared above.
            @($installErrors).Count | Should -Be $written.Count
            for ($i = 0; $i -lt $written.Count; $i++) {
                for ($j = 0; $j -lt $i; $j++) {
                    [object]::ReferenceEquals($installErrors[$i], $installErrors[$j]) | Should -BeFalse -Because "entry $i of -ErrorVariable is not entry $j again"
                }
                if ($Mode -eq "EnableException" -and $i -eq ($written.Count - 1)) {
                    [object]::ReferenceEquals($installErrors[$i], $stopEntry) | Should -BeTrue -Because "the last entry is the stop's"
                } else {
                    [object]::ReferenceEquals($installErrors[$i], $written[$i]) | Should -BeTrue -Because "entry $i of -ErrorVariable is the record written $i"
                }
            }
        }
    }

    # The Server.Query script method puts the caller's database back in its finally (#10555).
    It "leaves the caller's connection in the database it was in" {
        $contextServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database tempdb -NonPooledConnection -EnableException
        $contextServer.ConnectionContext.CurrentDatabase | Should -BeExactly "tempdb"
        $result = Get-DbaInstanceInstallDate -SqlInstance $contextServer -EnableException
        ([datetime]$result.SqlInstallDate) | Should -Be $installSqlDate
        $contextServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -BeExactly "tempdb"
        $contextServer.ConnectionContext.Disconnect()
    }

    # The two install-date reads are statements of the pin's body with no try: a login denied SELECT on both views makes each
    # $server.Query fail with the script method's record.
    Context "a login that may not read the install date" {
        BeforeAll {
            $deniedInstance = $TestConfig.InstanceSqlLogin
            $deniedAdmin = Connect-DbaInstance -SqlInstance $deniedInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException
            $deniedName = "dbatoolsci_iddeny_" + [guid]::NewGuid().ToString("N").Substring(0, 10)
            $deniedPassword = "P@ss" + [guid]::NewGuid().ToString("N") + "!"
            $deniedCred = New-Object System.Management.Automation.PSCredential -ArgumentList $deniedName, (ConvertTo-SecureString -String $deniedPassword -AsPlainText -Force)
            $null = $deniedAdmin.Query("USE [master]; CREATE LOGIN [$deniedName] WITH PASSWORD = N'$deniedPassword', CHECK_POLICY = OFF, DEFAULT_DATABASE = [master]; CREATE USER [$deniedName] FOR LOGIN [$deniedName]; DENY SELECT ON sys.server_principals TO [$deniedName]; DENY SELECT ON sys.sysservers TO [$deniedName];")
            $deniedCallers = New-Object System.Collections.ArrayList

            function New-NativeDeniedCaller {
                $caller = Connect-DbaInstance -SqlInstance $deniedInstance -SqlCredential $deniedCred -NonPooledConnection -EnableException
                $null = $deniedCallers.Add($caller)
                return $caller
            }

            # Independent reads: the script method's own record for each denied query, on the test's own denied connection.
            $referenceCaller = New-NativeDeniedCaller
            $principalFault = $null
            try {
                $null = $referenceCaller.Query("SELECT create_date FROM sys.server_principals WHERE sid = 0x010100000000000512000000", "master", $true)
            } catch {
                $principalFault = $PSItem
            }
            $serversFault = $null
            try {
                $null = $referenceCaller.Query("SELECT schemadate FROM dbo.sysservers", "master", $true)
            } catch {
                $serversFault = $PSItem
            }
            $installDateText = ([datetime]$installSqlDate).ToString("yyyy-MM-dd HH:mm:ss.fffffff")

            function Assert-NativeQueryFault {
                param($Record, $Reference)
                $Reference | Should -Not -BeNullOrEmpty
                $Record.FullyQualifiedErrorId | Should -BeLike "ScriptMethodRuntimeException*"
                $Record.Exception.GetType().FullName | Should -BeExactly $Reference.Exception.GetType().FullName
                $Record.Exception.Message | Should -BeExactly $Reference.Exception.Message
                $Record.Exception.Message | Should -BeLike 'Exception calling "Query" with "3" argument(s): *permission was denied*'
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "$($Reference.CategoryInfo.Category)"
                $Record.Exception.InnerException.GetType().FullName | Should -BeExactly $Reference.Exception.InnerException.GetType().FullName
                $Record.Exception.InnerException.Message | Should -BeExactly $Reference.Exception.InnerException.Message
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-NativeInstallCall {
                param([hashtable]$Arguments, [string]$Script = 'param($Arguments) Get-DbaInstanceInstallDate @Arguments | ForEach-Object { "row: " + $PSItem.SqlInstance + "=" + $(if ($null -eq $PSItem.SqlInstallDate) { "(null)" } else { ([datetime]$PSItem.SqlInstallDate).ToString("yyyy-MM-dd HH:mm:ss.fffffff") }) }; "next statement"')
                $callState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $callType = (Get-Command Get-DbaInstanceInstallDate -CommandType Cmdlet).ImplementingType
                $callEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaInstanceInstallDate", $callType, $null
                $callState.Commands.Add($callEntry)
                $callRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($callState)
                $callShell = [System.Management.Automation.PowerShell]::Create()
                $callOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $callStop = $null
                try {
                    $callRunspace.Open()
                    $callShell.Runspace = $callRunspace
                    $null = $callShell.AddScript($Script).AddArgument($Arguments)
                    try {
                        $null = $callShell.Invoke($null, $callOutput)
                    } catch {
                        # The stop leaves the runspace's script through Invoke, as a method call's exception.
                        $callStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Output = @($callOutput | ForEach-Object { "$PSItem" })
                        Errors = @($callShell.Streams.Error)
                        Stop   = $callStop
                    }
                } finally {
                    $callShell.Dispose()
                    $callRunspace.Dispose()
                }
            }
        }

        AfterAll {
            foreach ($caller in $deniedCallers) {
                try {
                    $caller.ConnectionContext.Disconnect()
                } catch {
                    # A caller may already be closed; the KILL below ends what is left.
                }
            }
            # Each KILL has its own TRY: a session may end between the SELECT and its KILL.
            $null = $deniedAdmin.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'BEGIN TRY KILL ' + CAST(session_id AS nvarchar(10)) + N'; END TRY BEGIN CATCH END CATCH; ' FROM sys.dm_exec_sessions WHERE login_name = N'$deniedName'; EXEC sys.sp_executesql @kill;")
            $null = $deniedAdmin.Query("USE [master]; IF DATABASE_PRINCIPAL_ID(N'$deniedName') IS NOT NULL DROP USER [$deniedName]; IF SUSER_ID(N'$deniedName') IS NOT NULL DROP LOGIN [$deniedName];")
        }

        It "writes the record of each denied query, returns the row with no date and goes on to the next instance" {
            $deniedCaller = New-NativeDeniedCaller
            $call = Invoke-NativeInstallCall -Arguments @{ SqlInstance = @($deniedCaller, $installServer) }
            $call.Stop | Should -BeNullOrEmpty
            $call.Errors.Count | Should -Be 2
            Assert-NativeQueryFault -Record $call.Errors[0] -Reference $principalFault
            Assert-NativeQueryFault -Record $call.Errors[1] -Reference $serversFault
            ($call.Output -join ",") | Should -BeExactly ("row: " + $deniedCaller.DomainInstanceName + "=(null),row: " + $installServer.DomainInstanceName + "=" + $installDateText + ",next statement")
        }

        # Correction stale-install-date: the pin's $sqlInstallDate kept the instance before's date, so the denied row showed
        # that date as its own and the sysservers retry never ran.
        It "gives the denied instance no date carried from the instance before it" {
            $deniedCaller = New-NativeDeniedCaller
            $call = Invoke-NativeInstallCall -Arguments @{ SqlInstance = @($installServer, $deniedCaller) }
            $call.Stop | Should -BeNullOrEmpty
            ($call.Output -join ",") | Should -BeExactly ("row: " + $installServer.DomainInstanceName + "=" + $installDateText + ",row: " + $deniedCaller.DomainInstanceName + "=(null),next statement")
            $call.Errors.Count | Should -Be 2
            Assert-NativeQueryFault -Record $call.Errors[0] -Reference $principalFault
            Assert-NativeQueryFault -Record $call.Errors[1] -Reference $serversFault
        }

        It "gives the denied instance no date carried from the instance piped before it" {
            $deniedCaller = New-NativeDeniedCaller
            $script = 'param($Arguments) $Arguments.SqlInstance | Get-DbaInstanceInstallDate | ForEach-Object { "row: " + $PSItem.SqlInstance + "=" + $(if ($null -eq $PSItem.SqlInstallDate) { "(null)" } else { ([datetime]$PSItem.SqlInstallDate).ToString("yyyy-MM-dd HH:mm:ss.fffffff") }) }; "next statement"'
            $call = Invoke-NativeInstallCall -Arguments @{ SqlInstance = @($installServer, $deniedCaller) } -Script $script
            $call.Stop | Should -BeNullOrEmpty
            ($call.Output -join ",") | Should -BeExactly ("row: " + $installServer.DomainInstanceName + "=" + $installDateText + ",row: " + $deniedCaller.DomainInstanceName + "=(null),next statement")
            $call.Errors.Count | Should -Be 2
            Assert-NativeQueryFault -Record $call.Errors[0] -Reference $principalFault
            Assert-NativeQueryFault -Record $call.Errors[1] -Reference $serversFault
        }

        It "lets a caller's try catch it, and the command does not go on" {
            $script = 'param($Arguments) try { Get-DbaInstanceInstallDate @Arguments | ForEach-Object { "row: " + $PSItem.SqlInstance }; "after the call" } catch { "caught: " + $PSItem.FullyQualifiedErrorId + " | " + $PSItem.Exception.Message }; "next statement"'
            $call = Invoke-NativeInstallCall -Arguments @{ SqlInstance = @((New-NativeDeniedCaller), $installServer) } -Script $script
            $call.Stop | Should -BeNullOrEmpty
            $call.Output.Count | Should -Be 2
            $call.Output[0] | Should -BeLike "caught: ScriptMethodRuntimeException*"
            $call.Output[0] | Should -BeLike ("caught: ScriptMethodRuntimeException* | " + [System.Management.Automation.WildcardPattern]::Escape($principalFault.Exception.Message))
            $call.Output[1] | Should -BeExactly "next statement"
        }

        # Keep-going rule: -EnableException stops at the record (the keep-going section's accepted difference).
        It "stops at the record under -EnableException, and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $call = Invoke-NativeInstallCall -Arguments @{ SqlInstance = @((New-NativeDeniedCaller), $installServer); EnableException = $true }
            $call.Stop | Should -BeNullOrEmpty
            $call.Errors.Count | Should -Be 1
            Assert-NativeQueryFault -Record $call.Errors[0] -Reference $principalFault
            ($call.Output -join ",") | Should -BeExactly "next statement"
        }

        # Outside any try, -ErrorAction Stop has the effect PowerShell gives the record a compiled command writes: the script stops there.
        It "turns the record into the stop -ErrorAction Stop gives, outside any try" {
            $call = Invoke-NativeInstallCall -Arguments @{ SqlInstance = @((New-NativeDeniedCaller), $installServer); ErrorAction = "Stop" }
            $call.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeQueryFault -Record $call.Stop.ErrorRecord -Reference $principalFault
            $call.Output | Should -Not -Contain "next statement"
            @($call.Output | Where-Object { $PSItem -like "row: *" }).Count | Should -Be 0
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # The pin returns one row there with no warning and no error (probe evidence pin-installdate-20261105.txt, both
            # editions): no NT AUTHORITY\SYSTEM login, so the sysservers row of master gives the date; no NetBIOS name, so
            # -IncludeWindows reads nothing.
            $azure = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database master -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $PSItem.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        # "The wait operation timed out": the lab reaches Azure over mobile internet (operator, azure-258).
                        if ($azureError -is [System.ComponentModel.Win32Exception] -and $azureError.NativeErrorCode -eq 258) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azurePrincipals = @($azure.ConnectionContext.ExecuteWithResults("SELECT create_date FROM sys.server_principals WHERE sid = 0x010100000000000512000000").Tables[0].Rows)
            $azureSchemaDate = [datetime]($azure.ConnectionContext.ExecuteScalar("SELECT schemadate FROM dbo.sysservers"))
        }

        AfterAll {
            if ($azure) { $azure.ConnectionContext.Disconnect() }
        }

        It "returns the logical server's date from sysservers, with no warning and no error" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azurePrincipals.Count | Should -Be 0
            foreach ($includeWindows in $false, $true) {
                $azureWarnings = @()
                $azureErrors = @()
                $rows = @(Get-DbaInstanceInstallDate -SqlInstance $azure -IncludeWindows:$includeWindows -WarningAction SilentlyContinue -WarningVariable azureWarnings -ErrorAction SilentlyContinue -ErrorVariable azureErrors)
                $azureWarnings.Count | Should -Be 0
                $azureErrors.Count | Should -Be 0
                $rows.Count | Should -Be 1
                $rows[0].ComputerName | Should -BeExactly $azure.ComputerName
                $rows[0].InstanceName | Should -BeNullOrEmpty
                $rows[0].SqlInstance | Should -BeExactly $azure.DomainInstanceName
                $rows[0].SqlInstallDate | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
                ([datetime]$rows[0].SqlInstallDate) | Should -Be $azureSchemaDate
                $rows[0].WindowsInstallDate | Should -BeNullOrEmpty
            }
            $after = try { $null = Get-DbaInstanceInstallDate -SqlInstance $azure -IncludeWindows -EnableException; "went on" } catch { "caught: " + $PSItem.FullyQualifiedErrorId }
            $after | Should -BeExactly "went on"
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $loginDate = [datetime]($loginServer.ConnectionContext.ExecuteScalar("SELECT create_date FROM sys.server_principals WHERE sid = 0x010100000000000512000000"))
        }

        It "works with -SqlCredential" {
            $result = Get-DbaInstanceInstallDate -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            ([datetime]$result.SqlInstallDate) | Should -Be $loginDate
            $result.SqlInstance | Should -BeExactly $loginServer.DomainInstanceName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            $result = Get-DbaInstanceInstallDate -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            { Get-DbaInstanceInstallDate -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }
}
