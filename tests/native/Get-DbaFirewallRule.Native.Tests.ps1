#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: sql-login N/A -- the pinned command has no SqlCredential and opens no SQL Server connection; Credential is a Windows credential for the target computer.
# NativeChecklist: azure-sqldb N/A -- the command reads the Windows Firewall rules (MSFT_NetFirewallRule in root\StandardCimv2) of the computer that hosts the instance; Azure SQL Database is a managed service with no host operating system or Windows Firewall, and its firewall is the server and database IP rule set. https://learn.microsoft.com/azure/azure-sql/database/firewall-configure
# NativeChecklist: whatif-confirm N/A -- the pinned command declares no SupportsShouldProcess and changes nothing on the target.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaFirewallRule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaFirewallRule" -Tag IntegrationTests {
    BeforeAll {
        $fwInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle
        $fwComputer = $fwInstance.ComputerName
        $fwSuffix = -join (1..8 | ForEach-Object { "{0:x}" -f (Get-Random -Maximum 16) })
        $fwFirst = "ZNATIVEA$fwSuffix"
        $fwSecond = "ZNATIVEB$fwSuffix"
        $fwAbsentInstance = "ZNATIVEC$fwSuffix"
        # The mirroring instance's rule sorts and is created after the other instance rules, and the
        # unmatched rule sorts and is created right after it, whichever order the store lists them in.
        $fwMirroring = "ZNATIVEZ$fwSuffix"
        $fwUnmatched = "zzdbatoolsnative $fwSuffix unmatched"
        $fwProgram = "C:\dbatoolsnative$fwSuffix\sqlservr.exe"
        $fwAbsentComputer = "dbatoolsnative-$fwSuffix-absent"

        # Disabled rules in the group New-DbaFirewallRule uses; they open no port on the target.
        $fwRules = @(
            @{ Name = "SQL Server instance $fwFirst"; Protocol = "TCP"; LocalPort = "1433"; Program = $fwProgram },
            @{ Name = "SQL Server instance $fwFirst (DAC)"; Protocol = "TCP"; LocalPort = "50121"; Program = $null },
            @{ Name = "SQL Server instance $fwSecond"; Protocol = "TCP"; LocalPort = "50122"; Program = $null },
            @{ Name = "SQL Server instance $fwMirroring (DatabaseMirroring)"; Protocol = "TCP"; LocalPort = "50123"; Program = $null },
            @{ Name = $fwUnmatched; Protocol = $null; LocalPort = $null; Program = $null }
        )

        $fwSession = New-PSSession -ComputerName $fwComputer -ErrorAction Stop
        $fwBrowserCreated = Invoke-Command -Session $fwSession -ArgumentList (, $fwRules) -ErrorAction Stop -ScriptBlock {
            param($rules)
            foreach ($rule in $rules) {
                $splatRule = @{
                    Name        = $rule.Name
                    DisplayName = $rule.Name
                    Group       = "SQL Server"
                    Direction   = "Inbound"
                    Action      = "Allow"
                    Enabled     = "False"
                    ErrorAction = "Stop"
                }
                if ($rule.Protocol) {
                    $splatRule.Protocol = $rule.Protocol
                    $splatRule.LocalPort = $rule.LocalPort
                }
                if ($rule.Program) {
                    $splatRule.Program = $rule.Program
                }
                $null = New-NetFirewallRule @splatRule
            }
            $browserCreated = $false
            if (-not (Get-NetFirewallRule -Name "SQL Server Browser" -ErrorAction SilentlyContinue)) {
                $splatBrowser = @{
                    Name        = "SQL Server Browser"
                    DisplayName = "SQL Server Browser"
                    Group       = "SQL Server"
                    Direction   = "Inbound"
                    Action      = "Allow"
                    Enabled     = "False"
                    Protocol    = "UDP"
                    LocalPort   = "1434"
                    ErrorAction = "Stop"
                }
                $null = New-NetFirewallRule @splatBrowser
                $browserCreated = $true
            }
            $browserCreated
        }

        function Get-FwIndependentRule {
            param($Name)
            Invoke-Command -Session $fwSession -ArgumentList $Name -ErrorAction Stop -ScriptBlock {
                param($ruleName)
                $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction Stop
                $port = $rule | Get-NetFirewallPortFilter
                $application = $rule | Get-NetFirewallApplicationFilter
                [PSCustomObject]@{
                    DisplayName = $rule.DisplayName
                    Group       = $rule.Group
                    Protocol    = $port.Protocol
                    LocalPort   = @($port.LocalPort)
                    Program     = $application.Program
                }
            }
        }

        function Get-FwGroupRuleName {
            Invoke-Command -Session $fwSession -ErrorAction Stop -ScriptBlock {
                @(Get-NetFirewallRule -Group "SQL Server" -ErrorAction SilentlyContinue | ForEach-Object { $PSItem.Name })
            }
        }
    }

    AfterAll {
        if ($fwSession) {
            try {
                Invoke-Command -Session $fwSession -ArgumentList $fwSuffix, $fwBrowserCreated -ScriptBlock {
                    param($suffix, $browserCreated)
                    Get-NetFirewallRule -Group "SQL Server" -ErrorAction SilentlyContinue | Where-Object { $PSItem.Name -like "*$suffix*" } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
                    if ($browserCreated) {
                        Remove-NetFirewallRule -Name "SQL Server Browser" -ErrorAction SilentlyContinue
                    }
                }
            } finally {
                Remove-PSSession -Session $fwSession
            }
        }
    }

    It "returns every rule of the SQL Server group with its port filter, application filter and raw rule" {
        $allRules = @(Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance -EnableException)
        @($allRules.Name | Sort-Object) | Should -Be @(Get-FwGroupRuleName | Sort-Object)

        $engineRule = @($allRules | Where-Object Name -eq "SQL Server instance $fwFirst")
        $engineRule.Count | Should -Be 1
        $expected = Get-FwIndependentRule -Name "SQL Server instance $fwFirst"
        ($engineRule[0].PSObject.Properties.Name -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,DisplayName,Name,Type,Protocol,LocalPort,Program,Rule,Credential"
        ($engineRule[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,DisplayName,Type,Protocol,LocalPort,Program"
        $engineRule[0].ComputerName | Should -BeExactly $fwComputer
        $engineRule[0].InstanceName | Should -BeExactly $fwFirst
        $engineRule[0].SqlInstance | Should -BeExactly "$fwComputer\$fwFirst"
        $engineRule[0].Type | Should -BeExactly "Engine"
        $engineRule[0].DisplayName | Should -BeExactly $expected.DisplayName
        $engineRule[0].Protocol | Should -BeExactly $expected.Protocol
        $engineRule[0].Protocol | Should -BeExactly "TCP"
        @($engineRule[0].LocalPort) | Should -Be @($expected.LocalPort)
        @($engineRule[0].LocalPort) | Should -Be @("1433")
        $engineRule[0].Program | Should -BeExactly $expected.Program
        $engineRule[0].Program | Should -BeExactly $fwProgram
        $engineRule[0].Rule.InstanceID | Should -BeExactly "SQL Server instance $fwFirst"
        $engineRule[0].Rule.RuleGroup | Should -BeExactly "SQL Server"
        ($engineRule[0].Rule.PSObject.TypeNames -join ";") | Should -Match "MSFT_NetFirewallRule"
        $engineRule[0].Credential | Should -BeNullOrEmpty

        $dacRule = @($allRules | Where-Object Name -eq "SQL Server instance $fwFirst (DAC)")
        $dacRule.Type | Should -BeExactly "DAC"
        $dacRule.InstanceName | Should -BeExactly $fwFirst
        $dacRule.SqlInstance | Should -BeExactly "$fwComputer\$fwFirst"
        $dacRule.Program | Should -BeExactly (Get-FwIndependentRule -Name "SQL Server instance $fwFirst (DAC)").Program

        $mirroringRule = @($allRules | Where-Object Name -eq "SQL Server instance $fwMirroring (DatabaseMirroring)")
        $mirroringRule.Type | Should -BeExactly "DatabaseMirroring"
        $mirroringRule.InstanceName | Should -BeExactly $fwMirroring
        $mirroringRule.SqlInstance | Should -BeExactly "$fwComputer\$fwMirroring"
        @($mirroringRule.LocalPort) | Should -Be @("50123")

        # A rule without protocol, port or program shows them as Get-NetFirewallPortFilter and
        # Get-NetFirewallApplicationFilter do: "Any", @("Any") and "Any".
        $anyRule = @($allRules | Where-Object Name -eq $fwUnmatched)
        $anyExpected = Get-FwIndependentRule -Name $fwUnmatched
        $anyRule[0].Protocol | Should -BeExactly $anyExpected.Protocol
        $anyRule[0].Protocol | Should -BeExactly "Any"
        @($anyRule[0].LocalPort) | Should -Be @($anyExpected.LocalPort)
        @($anyRule[0].LocalPort) | Should -Be @("Any")
        $anyRule[0].Program | Should -BeExactly $anyExpected.Program
        $anyRule[0].Program | Should -BeExactly "Any"

        $browserRule = @($allRules | Where-Object Name -eq "SQL Server Browser")
        $browserRule.Count | Should -Be 1
        $browserRule[0].Type | Should -BeExactly "Browser"
        $browserRule[0].InstanceName | Should -BeNullOrEmpty
        $browserRule[0].SqlInstance | Should -BeNullOrEmpty
    }

    It "leaves Type, InstanceName and SqlInstance empty for a group rule whose name matches no rule pattern" {
        $allRules = @(Get-DbaFirewallRule -SqlInstance $TestConfig.InstanceSingle -Type AllInstance -EnableException)
        $unmatchedRule = @($allRules | Where-Object Name -eq $fwUnmatched)
        $unmatchedRule.Count | Should -Be 1
        $unmatchedRule[0].Type | Should -BeNullOrEmpty
        $unmatchedRule[0].InstanceName | Should -BeNullOrEmpty
        $unmatchedRule[0].SqlInstance | Should -BeNullOrEmpty
        @(Get-DbaFirewallRule -SqlInstance "$fwComputer\$fwMirroring" -Type DatabaseMirroring -EnableException).Name | Should -Be @("SQL Server instance $fwMirroring (DatabaseMirroring)")
        @(Get-DbaFirewallRule -SqlInstance "$fwComputer\$fwFirst" -Type Engine, DAC -EnableException).Name | Should -Be @("SQL Server instance $fwFirst", "SQL Server instance $fwFirst (DAC)")
    }

    It "returns the instance and DAC rules but no Browser rule for an instance whose rule opens port 1433" {
        $firstStreams = @(Get-DbaFirewallRule -SqlInstance "$fwComputer\$fwFirst" -EnableException -Verbose 4>&1)
        $firstRules = @($firstStreams | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })
        $firstMessages = @($firstStreams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
        @($firstRules.Name | Sort-Object) | Should -Be @("SQL Server instance $fwFirst", "SQL Server instance $fwFirst (DAC)")
        @($firstMessages | Where-Object { $PSItem -like "*Returning rule for instance, DAC and maybe for Browser*" }).Count | Should -Be 1
        @($firstMessages | Where-Object { $PSItem -like "*No rule for Browser needed*" }).Count | Should -Be 1
        @($firstMessages | Where-Object { $PSItem -match "Get-NetFirewallRule was successful, we have (\d+) rules\." }).Count | Should -Be 1
    }

    It "adds the Browser rule for an instance whose rule opens another port" {
        $secondRules = @(Get-DbaFirewallRule -SqlInstance "$fwComputer\$fwSecond" -EnableException)
        @($secondRules.Name) | Should -Be @("SQL Server instance $fwSecond", "SQL Server Browser")
        $secondRules[1].Type | Should -BeExactly "Browser"
        $secondRules[1].ComputerName | Should -BeExactly $fwComputer
    }

    It "returns the Browser rule alone for -Type Browser and nothing for an instance without rules" {
        @(Get-DbaFirewallRule -SqlInstance "$fwComputer\$fwFirst" -Type Browser -EnableException).Name | Should -Be @("SQL Server Browser")
        $absentStreams = @(Get-DbaFirewallRule -SqlInstance "$fwComputer\$fwAbsentInstance" -EnableException -Verbose 4>&1)
        @($absentStreams | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
        @($absentStreams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No rule found for instance*" }).Count | Should -Be 1
    }

    It "names a group with no rule as Get-NetFirewallRule does in its not-found message" {
        $missingGroup = "dbatoolsnative $fwSuffix missing"
        $notFound = Invoke-Command -Session $fwSession -ArgumentList $missingGroup -ErrorAction Stop -ScriptBlock {
            param($group)
            $null = Get-NetFirewallRule -Group $group -ErrorAction SilentlyContinue -ErrorVariable notFoundErrors
            "$($notFoundErrors[0])"
        }
        $notFound | Should -BeExactly "No MSFT_NetFirewallRule objects found with property 'RuleGroup' equal to '$missingGroup'.  Verify the value of the property and retry."
    }

    It "returns each piped instance's rules in input order" -Tag "NativeChecklist:pipeline-multiple" {
        $pipedRules = @("$fwComputer\$fwFirst", "$fwComputer\$fwSecond" | Get-DbaFirewallRule -Type Engine -EnableException)
        @($pipedRules.Name) | Should -Be @("SQL Server instance $fwFirst", "SQL Server instance $fwSecond")
        @($pipedRules.SqlInstance) | Should -Be @("$fwComputer\$fwFirst", "$fwComputer\$fwSecond")
    }

    It "warns for a computer it cannot reach and goes on with the next instance" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $continuedRules = @(Get-DbaFirewallRule -SqlInstance "$fwAbsentComputer\$fwFirst", "$fwComputer\$fwFirst" -Type Engine -EnableException:$false -WarningVariable continuedWarnings -WarningAction SilentlyContinue)
        @($continuedRules.Name) | Should -Be @("SQL Server instance $fwFirst")
        @($continuedWarnings).Count | Should -Be 1
        "$($continuedWarnings[0])" | Should -BeLike "*Failed to execute command on $fwAbsentComputer for instance $fwFirst.*"
    }

    It "keeps the earlier output, then stops at a computer it cannot reach under EnableException" -Tag "NativeChecklist:enable-exception" {
        $stoppedRules = New-Object System.Collections.ArrayList
        $stoppedError = $null
        try {
            Get-DbaFirewallRule -SqlInstance "$fwComputer\$fwFirst", "$fwAbsentComputer\$fwFirst", "$fwComputer\$fwSecond" -Type Engine -EnableException | ForEach-Object { $null = $stoppedRules.Add($PSItem) }
        } catch {
            $stoppedError = $PSItem
        }
        $stoppedError | Should -Not -BeNullOrEmpty
        $stoppedError.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaFirewallRule*"
        @($stoppedRules.Name) | Should -Be @("SQL Server instance $fwFirst")
    }

    It "reports a computer it cannot read over CIM instead of returning rules without their filters" {
        # With CimRM and CimDCOM switched off and WMI and PowerShell Remoting on, Get-DbaCmObject still
        # reads the computer, but a rule read on those rungs carries no CIM association to its port and
        # application filters, so the command must not return it.
        $fwKey = $fwComputer.ToLowerInvariant()
        $fwHost = [Dataplat.Dbatools.Connection.ConnectionHost]
        $fwSavedFlags = @($fwHost::DisableConnectionCimRM, $fwHost::DisableConnectionCimDCOM, $fwHost::DisableConnectionWMI, $fwHost::DisableConnectionPowerShellRemoting)
        $fwSavedConnection = $null
        if ($fwHost::Connections.ContainsKey($fwKey)) {
            $fwSavedConnection = $fwHost::Connections[$fwKey]
            $null = $fwHost::Connections.Remove($fwKey)
        }
        try {
            $fwHost::DisableConnectionCimRM = $true
            $fwHost::DisableConnectionCimDCOM = $true
            $fwHost::DisableConnectionWMI = $false
            $fwHost::DisableConnectionPowerShellRemoting = $false

            $fwUnreadRules = @(Get-DbaFirewallRule -SqlInstance "$fwComputer\$fwFirst" -Type AllInstance -WarningVariable fwUnreadWarnings -WarningAction SilentlyContinue)
            $fwUnreadRules.Count | Should -Be 0
            @($fwUnreadWarnings).Count | Should -Be 1
            "$($fwUnreadWarnings[0])" | Should -BeLike "*Failed to execute command on $fwComputer for instance $fwFirst.*"

            $fwUnreadError = $null
            try {
                $null = Get-DbaFirewallRule -SqlInstance "$fwComputer\$fwFirst" -Type AllInstance -EnableException
            } catch {
                $fwUnreadError = $PSItem
            }
            $fwUnreadError | Should -Not -BeNullOrEmpty
            $fwUnreadError.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaFirewallRule*"

            # The PowerShell Remoting rung does reach the computer in this setup.
            @(Get-DbaCmObject -ClassName Win32_TimeZone -ComputerName $fwComputer -DoNotUse CimRM, CimDCOM, Wmi -EnableException).Count | Should -Be 1
        } finally {
            $fwHost::DisableConnectionCimRM = $fwSavedFlags[0]
            $fwHost::DisableConnectionCimDCOM = $fwSavedFlags[1]
            $fwHost::DisableConnectionWMI = $fwSavedFlags[2]
            $fwHost::DisableConnectionPowerShellRemoting = $fwSavedFlags[3]
            $null = $fwHost::Connections.Remove($fwKey)
            if ($fwSavedConnection) {
                $fwHost::Connections[$fwKey] = $fwSavedConnection
            }
        }
    }
}
