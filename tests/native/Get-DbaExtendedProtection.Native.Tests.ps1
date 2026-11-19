#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: sql-login N/A -- the pinned command has no SqlCredential and opens no SQL connection; Credential is a Windows credential.
# NativeChecklist: azure-sqldb N/A -- the command reads SQL Server network protocol settings from the host's Windows registry through SQL WMI; Azure SQL Database is a managed database service with no host registry, SQL WMI or Configuration Manager network settings. https://learn.microsoft.com/azure/azure-sql/database/sql-database-paas-overview
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaExtendedProtection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaExtendedProtection" -Tag IntegrationTests {
    BeforeAll {
        $nepInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle
        $nepComputer = $nepInstance.ComputerName
        $nepInstanceName = $nepInstance.InstanceName
        $nepSession = New-PSSession -ComputerName $nepComputer -ErrorAction Stop

        # The pinned function's own expressions, run on the target's registry: the independent expected values.
        $nepReadTarget = {
            param($instanceName)
            $instanceMap = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction Stop
            $instanceId = $instanceMap.$instanceName
            if (-not $instanceId) { throw 'Missing SQL instance registry mapping.' }
            $settings = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib" -ErrorAction Stop
            $extendedProtection = $settings.ExtendedProtection
            $acceptedSpns = @($settings.AcceptedSPNs -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($PSItem) })
            [pscustomobject]@{
                ComputerName       = $env:COMPUTERNAME
                ExtendedProtection = "$extendedProtection - $(switch ($extendedProtection) { 0 { "Off" } 1 { "Allowed" } 2 { "Required" } })"
                AcceptedSpns       = [string[]]$acceptedSpns
                SpnCount           = $acceptedSpns.Count
            }
        }

        # Denies the caller QueryValues on the instance's own SuperSocketNetLib key on the target ($Deny), or takes that one rule back,
        # then reads the key as the pinned remote scriptblock does, as the caller: the caught record is the one the pinned Stop-Function gets.
        # The SQL service reads the key as its own account, so the denial reaches only this caller.
        # The key is opened for its access rules only (ReadPermissions, ChangePermissions), never through Get-Acl or Set-Acl:
        # they failed on every leg of result 20261104T2327280428588Z with "Cannot find path" (no rule was left, checked by the
        # manager afterwards), and once QueryValues is denied a read-access open of the key is refused.
        $nepSetDenial = {
            param($instanceName, [bool]$Deny)
            $instanceId = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction Stop).$instanceName
            if (-not $instanceId) { throw 'Missing SQL instance registry mapping.' }
            $subKey = "SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib"
            $caller = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule -ArgumentList $caller, ([System.Security.AccessControl.RegistryRights]::QueryValues), ([System.Security.AccessControl.AccessControlType]::Deny)
            $rights = [System.Security.AccessControl.RegistryRights]::ReadPermissions -bor [System.Security.AccessControl.RegistryRights]::ChangePermissions
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKey, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, $rights)
            if (-not $key) { throw "Missing registry key HKLM\$subKey." }
            try {
                $acl = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
                if ($Deny) {
                    $acl.AddAccessRule($rule)
                } else {
                    $null = $acl.RemoveAccessRule($rule)
                }
                $key.SetAccessControl($acl)
            } finally {
                $key.Close()
            }
            try {
                $null = Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib" -ErrorAction Stop
                [pscustomobject]@{ Denied = $false; Category = $null; Message = $null }
            } catch {
                [pscustomobject]@{ Denied = $true; Category = "$($PSItem.CategoryInfo.Category)"; Message = $PSItem.Exception.Message }
            }
        }

        # A rule left by an earlier run that stopped between its denial and its restore goes before any test starts.
        $nepPreclean = Invoke-Command -Session $nepSession -ArgumentList $nepInstanceName, $false -ScriptBlock $nepSetDenial -ErrorAction Stop
        if ($nepPreclean.Denied) { throw "The caller still may not read the network key: $($nepPreclean.Message)" }

        # Scratch registry keys on this computer, one root per run so parallel lanes never share one.
        $nepScratchName = 'SOFTWARE\dbatoolsci-nep-' + [guid]::NewGuid().ToString('N')
        $nepScratchPath = 'HKLM:\' + $nepScratchName

        function New-NepScratchKey {
            param([string]$Case)
            $path = $nepScratchPath + '\' + $Case + '\MSSQLServer\SuperSocketNetLib'
            $null = New-Item -Path $path -Force -ErrorAction Stop
            $path
        }

        function Get-NepPinnedText {
            param($Settings)
            $extendedProtection = $Settings.ExtendedProtection
            "$extendedProtection - $(switch ($extendedProtection) { 0 { "Off" } 1 { "Allowed" } 2 { "Required" } })"
        }

        function Get-NepPinnedSpns {
            param($Settings)
            , @($Settings.AcceptedSPNs -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($PSItem) })
        }
    }

    AfterAll {
        try {
            if ($nepSession) { Remove-PSSession -Session $nepSession }
        } finally {
            if (Test-Path -LiteralPath $nepScratchPath) {
                Remove-Item -LiteralPath $nepScratchPath -Recurse -Force -ErrorAction Stop
            }
        }
    }

    It "reports the instance's level and accepted SPNs as the pinned expressions read them" -Tag "NativeChecklist:switch-false" {
        # The pinned Get and Set tests change these values on InstanceRestart; read before and after so a
        # parallel lane's change between the reads is retried rather than misread.
        $nepAttempt = 0
        do {
            $nepAttempt++
            $nepBefore = Invoke-Command -Session $nepSession -ArgumentList $nepInstanceName -ScriptBlock $nepReadTarget -ErrorAction Stop
            $nepOutput = @(Get-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -EnableException:$false)
            $nepAfter = Invoke-Command -Session $nepSession -ArgumentList $nepInstanceName -ScriptBlock $nepReadTarget -ErrorAction Stop
            $nepStable = ($nepBefore.ExtendedProtection -eq $nepAfter.ExtendedProtection) -and ((@($nepBefore.AcceptedSpns) -join '|') -eq (@($nepAfter.AcceptedSpns) -join '|'))
        } while (-not $nepStable -and $nepAttempt -lt 3)
        $nepStable | Should -BeTrue

        $nepOutput.Count | Should -Be 1
        ($nepOutput[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'ComputerName,InstanceName,SqlInstance,ExtendedProtection,AcceptedSpns'
        $nepOutput[0].PSObject.TypeNames[0] | Should -BeExactly 'Selected.System.Management.Automation.PSCustomObject'
        $nepOutput[0].ComputerName | Should -BeExactly $nepBefore.ComputerName
        $nepOutput[0].InstanceName | Should -BeExactly $nepInstanceName
        $nepOutput[0].SqlInstance | Should -Not -BeNullOrEmpty
        $nepOutput[0].ExtendedProtection | Should -BeExactly $nepBefore.ExtendedProtection
        $nepOutput[0].ExtendedProtection | Should -Match '^[0-2] - (Off|Allowed|Required)$'
        ($nepOutput[0].AcceptedSpns -is [object[]]) | Should -BeTrue
        @($nepOutput[0].AcceptedSpns).Count | Should -Be $nepBefore.SpnCount
        (@($nepOutput[0].AcceptedSpns) -join '|') | Should -BeExactly (@($nepBefore.AcceptedSpns) -join '|')
    }

    It "returns nothing under WhatIf" -Tag "NativeChecklist:whatif-confirm" {
        @(Get-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -WhatIf -EnableException).Count | Should -Be 0
    }

    It "continues around a missing middle service and returns both other records" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure" {
        $nepMissing = $nepComputer + '\NM' + [guid]::NewGuid().ToString('N').Substring(0, 10)
        $nepWarnings = @()
        $nepOutput = @(@($TestConfig.InstanceSingle, $nepMissing, $TestConfig.InstanceSingle) | Get-DbaExtendedProtection -WarningAction SilentlyContinue -WarningVariable nepWarnings)
        $nepOutput.Count | Should -Be 2
        $nepOutput[0].InstanceName | Should -BeExactly $nepInstanceName
        $nepOutput[1].InstanceName | Should -BeExactly $nepInstanceName
        ($nepWarnings -join ' ') | Should -BeLike "*Can't find instance*"
    }

    It "keeps earlier output, then stops with the missing service's record under EnableException" -Tag "NativeChecklist:enable-exception" {
        $nepMissing = $nepComputer + '\NM' + [guid]::NewGuid().ToString('N').Substring(0, 10)
        $nepSeen = New-Object System.Collections.ArrayList
        $nepError = $null
        try {
            @($TestConfig.InstanceSingle, $nepMissing, $TestConfig.InstanceSingle) | Get-DbaExtendedProtection -EnableException | ForEach-Object { $null = $nepSeen.Add($PSItem) }
        } catch {
            $nepError = $PSItem
        }
        $nepSeen.Count | Should -Be 1
        $nepError | Should -Not -BeNullOrEmpty
        $nepError.CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $nepError.Exception.Message | Should -BeLike "*Can't find instance*"
    }

    It "does not default explicit null or empty instance input to the local machine" {
        @(Get-DbaExtendedProtection -SqlInstance $null -EnableException).Count | Should -Be 0
        @(Get-DbaExtendedProtection -SqlInstance @() -EnableException).Count | Should -Be 0
    }

    It "reads each registry kind as Get-ItemProperty does and formats it as the pinned expressions do" {
        $nepCases = @(
            @{ Case = 'dword-sz'; Values = @(
                    @{ Name = 'ExtendedProtection'; Type = 'DWord'; Value = 2 },
                    @{ Name = 'AcceptedSPNs'; Type = 'String'; Value = 'MSSQLSvc/nep-a:1433; MSSQLSvc/nep-b:1433;; ;' }) },
            @{ Case = 'dword-multi'; Values = @(
                    @{ Name = 'extendedprotection'; Type = 'DWord'; Value = 1 },
                    @{ Name = 'AcceptedSPNs'; Type = 'MultiString'; Value = [string[]]@('MSSQLSvc/nep-x;MSSQLSvc/nep-y', 'MSSQLSvc/nep-z') }) },
            @{ Case = 'qword-expand'; Values = @(
                    @{ Name = 'ExtendedProtection'; Type = 'QWord'; Value = 0 },
                    @{ Name = 'AcceptedSPNs'; Type = 'ExpandString'; Value = 'MSSQLSvc/%COMPUTERNAME%:1433;MSSQLSvc/nep-e' }) },
            @{ Case = 'string-level'; Values = @(
                    @{ Name = 'ExtendedProtection'; Type = 'String'; Value = '2' }) },
            @{ Case = 'empty'; Values = @() }
        )
        try {
            foreach ($nepCase in $nepCases) {
                $nepPath = New-NepScratchKey -Case $nepCase.Case
                foreach ($nepValue in $nepCase.Values) {
                    $null = New-ItemProperty -LiteralPath $nepPath -Name $nepValue.Name -PropertyType $nepValue.Type -Value $nepValue.Value -ErrorAction Stop
                }
                $nepPinned = Get-ItemProperty -LiteralPath $nepPath -ErrorAction Stop
                $nepRead = [Dataplat.Dbatools.Commands.ExtendedProtectionRegistry]::Read($env:COMPUTERNAME, $nepScratchName + '\' + $nepCase.Case, $null)

                if ($null -eq $nepPinned.ExtendedProtection) {
                    $nepRead.ExtendedProtection | Should -BeNullOrEmpty -Because $nepCase.Case
                } else {
                    $nepRead.ExtendedProtection.GetType().FullName | Should -BeExactly $nepPinned.ExtendedProtection.GetType().FullName -Because $nepCase.Case
                }
                (@($nepRead.AcceptedSpns) -join '|') | Should -BeExactly (@($nepPinned.AcceptedSPNs) -join '|') -Because $nepCase.Case
                $nepRead.ComputerName | Should -BeExactly $env:COMPUTERNAME -Because $nepCase.Case
                [Dataplat.Dbatools.Commands.ExtendedProtectionCmdlet]::ProtectionText($nepRead.ExtendedProtection) | Should -BeExactly (Get-NepPinnedText -Settings $nepPinned) -Because $nepCase.Case
                $nepSpns = [Dataplat.Dbatools.Commands.ExtendedProtectionCmdlet]::SpnList($nepRead.AcceptedSpns)
                $nepExpected = Get-NepPinnedSpns -Settings $nepPinned
                $nepSpns.Count | Should -Be $nepExpected.Count -Because $nepCase.Case
                ($nepSpns -join '|') | Should -BeExactly ($nepExpected -join '|') -Because $nepCase.Case
            }
        } finally {
            if (Test-Path -LiteralPath $nepScratchPath) {
                Remove-Item -LiteralPath $nepScratchPath -Recurse -Force -ErrorAction Stop
            }
        }
    }

    It "reads the local registry with a supplied credential, which WMI would refuse locally" {
        $nepUnused = New-Object System.Management.Automation.PSCredential ('native-unused-user', (ConvertTo-SecureString 'native-unused-password' -AsPlainText -Force))
        try {
            $nepPath = New-NepScratchKey -Case 'credential'
            $null = New-ItemProperty -LiteralPath $nepPath -Name ExtendedProtection -PropertyType DWord -Value 1 -ErrorAction Stop
            $nepRead = [Dataplat.Dbatools.Commands.ExtendedProtectionRegistry]::Read($env:COMPUTERNAME, $nepScratchName + '\credential', $nepUnused)
            $nepRead.ExtendedProtection | Should -Be 1
        } finally {
            if (Test-Path -LiteralPath $nepScratchPath) {
                Remove-Item -LiteralPath $nepScratchPath -Recurse -Force -ErrorAction Stop
            }
        }
    }

    It "throws for a missing network key, as Get-ItemProperty under ErrorAction Stop does" {
        { [Dataplat.Dbatools.Commands.ExtendedProtectionRegistry]::Read($env:COMPUTERNAME, $nepScratchName + '\absent', $null) } | Should -Throw
        Test-Path -LiteralPath $nepScratchPath | Should -BeFalse
    }

    It "writes each value as Set-ItemProperty writes it on the same starting key" {
        $nepWrites = @(
            @{ Case = 'keep-dword'; Start = @(@{ Name = 'ExtendedProtection'; Type = 'DWord'; Value = 0 }, @{ Name = 'AcceptedSPNs'; Type = 'String'; Value = 'MSSQLSvc/old' })
                SetLevel = $true; Level = '2'; SetSpns = $true; Spns = 'MSSQLSvc/nep-a:1433;MSSQLSvc/nep-b:1433' },
            @{ Case = 'keep-multi'; Start = @(@{ Name = 'ExtendedProtection'; Type = 'DWord'; Value = 1 }, @{ Name = 'AcceptedSPNs'; Type = 'MultiString'; Value = [string[]]@('MSSQLSvc/old') })
                SetLevel = $false; Level = 0; SetSpns = $true; Spns = 'MSSQLSvc/nep-c;MSSQLSvc/nep-d' },
            @{ Case = 'new-values'; Start = @()
                SetLevel = $true; Level = 1; SetSpns = $true; Spns = '' },
            @{ Case = 'level-only'; Start = @(@{ Name = 'AcceptedSPNs'; Type = 'String'; Value = 'MSSQLSvc/kept' })
                SetLevel = $true; Level = 0; SetSpns = $false; Spns = '' }
        )
        try {
            foreach ($nepWrite in $nepWrites) {
                $nepPinnedPath = New-NepScratchKey -Case ($nepWrite.Case + '-pin')
                $nepPortPath = New-NepScratchKey -Case ($nepWrite.Case + '-port')
                foreach ($nepPath in @($nepPinnedPath, $nepPortPath)) {
                    foreach ($nepValue in $nepWrite.Start) {
                        $null = New-ItemProperty -LiteralPath $nepPath -Name $nepValue.Name -PropertyType $nepValue.Type -Value $nepValue.Value -ErrorAction Stop
                    }
                }
                if ($nepWrite.SetLevel) { Set-ItemProperty -LiteralPath $nepPinnedPath -Name ExtendedProtection -Value $nepWrite.Level -ErrorAction Stop }
                if ($nepWrite.SetSpns) { Set-ItemProperty -LiteralPath $nepPinnedPath -Name AcceptedSPNs -Value $nepWrite.Spns -ErrorAction Stop }

                $nepRead = [Dataplat.Dbatools.Commands.ExtendedProtectionRegistry]::Write($env:COMPUTERNAME, $nepScratchName + '\' + $nepWrite.Case + '-port', $null, $nepWrite.SetLevel, $nepWrite.Level, $nepWrite.SetSpns, $nepWrite.Spns)

                $nepPinnedKey = Get-Item -LiteralPath $nepPinnedPath -ErrorAction Stop
                $nepPortKey = Get-Item -LiteralPath $nepPortPath -ErrorAction Stop
                (@($nepPortKey.GetValueNames() | Sort-Object) -join ',') | Should -BeExactly (@($nepPinnedKey.GetValueNames() | Sort-Object) -join ',') -Because $nepWrite.Case
                foreach ($nepName in $nepPinnedKey.GetValueNames()) {
                    $nepPortKey.GetValueKind($nepName) | Should -Be $nepPinnedKey.GetValueKind($nepName) -Because ($nepWrite.Case + ' ' + $nepName)
                    (@($nepPortKey.GetValue($nepName)) -join '|') | Should -BeExactly (@($nepPinnedKey.GetValue($nepName)) -join '|') -Because ($nepWrite.Case + ' ' + $nepName)
                }
                $nepPinnedSettings = Get-ItemProperty -LiteralPath $nepPinnedPath -ErrorAction Stop
                [Dataplat.Dbatools.Commands.ExtendedProtectionCmdlet]::ProtectionText($nepRead.ExtendedProtection) | Should -BeExactly (Get-NepPinnedText -Settings $nepPinnedSettings) -Because $nepWrite.Case
                ([Dataplat.Dbatools.Commands.ExtendedProtectionCmdlet]::SpnList($nepRead.AcceptedSpns) -join '|') | Should -BeExactly ((Get-NepPinnedSpns -Settings $nepPinnedSettings) -join '|') -Because $nepWrite.Case
                $nepPinnedKey.Close()
                $nepPortKey.Close()
            }
        } finally {
            if (Test-Path -LiteralPath $nepScratchPath) {
                Remove-Item -LiteralPath $nepScratchPath -Recurse -Force -ErrorAction Stop
            }
        }
    }

    Context "A network key the caller may not read" {
        AfterAll {
            # The one denial rule goes on every path, even when the test failed before its own finally.
            $null = Invoke-Command -Session $nepSession -ArgumentList $nepInstanceName, $false -ScriptBlock $nepSetDenial -ErrorAction Stop
        }

        It "reports it with the pinned PermissionDenied record, a warning on a plain call and a throw under EnableException" {
            try {
                $nepPinned = Invoke-Command -Session $nepSession -ArgumentList $nepInstanceName, $true -ScriptBlock $nepSetDenial -ErrorAction Stop
                $nepPinned.Denied | Should -BeTrue
                $nepPinned.Category | Should -BeExactly 'PermissionDenied'

                $nepWarnings = @()
                $nepOutput = @(Get-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue -WarningVariable nepWarnings)
                $nepOutput.Count | Should -Be 0
                @($nepWarnings).Count | Should -Be 1
                "$($nepWarnings[0])" | Should -BeLike "*Failed to connect to * using PowerShell remoting | $($nepPinned.Message)"

                $nepError = $null
                try {
                    $null = Get-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -EnableException -WarningAction SilentlyContinue
                } catch {
                    $nepError = $PSItem
                }
                $nepError | Should -Not -BeNullOrEmpty
                "$($nepError.CategoryInfo.Category)" | Should -BeExactly 'PermissionDenied'
                $nepError.Exception.Message | Should -BeExactly $nepPinned.Message
                $nepError.FullyQualifiedErrorId | Should -BeLike 'dbatools_Get-DbaExtendedProtection*'
            } finally {
                $nepRestored = Invoke-Command -Session $nepSession -ArgumentList $nepInstanceName, $false -ScriptBlock $nepSetDenial -ErrorAction Stop
            }
            $nepRestored.Denied | Should -BeFalse
        }
    }
}
