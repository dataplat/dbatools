#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPowerPlan",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command only reads Windows power plans and has no SupportsShouldProcess.
# NativeChecklist: sql-login N/A -- The pinned command has Credential for Windows management, not SqlCredential or a SQL connection.
# NativeChecklist: azure-sqldb N/A -- Windows power plans belong to the host operating system; Azure SQL Database is a managed database service without an accessible host. https://learn.microsoft.com/azure/azure-sql/database/sql-database-paas-overview
Describe "Native Get-DbaPowerPlan" -Tag IntegrationTests {
    BeforeAll {
        $nativePowerInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle
        $nativePowerComputer = $nativePowerInstance.ComputerName
        $nativePowerUnique = [guid]::NewGuid().ToString("N")
        $nativePowerMissing = "nativepower$nativePowerUnique.invalid"
        $splatNativePowerRead = @{
            ComputerName = $nativePowerComputer
            Namespace    = "root\cimv2\power"
            ClassName    = "Win32_PowerPlan"
            ErrorAction  = "Stop"
        }
        $nativePowerExpected = @(Get-CimInstance @splatNativePowerRead)
        $nativePowerActive = @($nativePowerExpected | Where-Object IsActive -eq $true)
    }

    It "returns the provider's active plan with its public properties and default view" {
        $nativePowerExpected.Count | Should -BeGreaterThan 0
        $nativePowerActive.Count | Should -Be 1
        $nativePowerRows = @(Get-DbaPowerPlan -ComputerName $nativePowerComputer -EnableException)
        $nativePowerRows.Count | Should -Be 1
        $nativePowerRow = $nativePowerRows[0]
        @($nativePowerRow.PSObject.Properties.Name) | Should -Be @("ComputerName", "InstanceId", "PowerPlan", "Credential")
        $nativePowerRow.ComputerName | Should -BeOfType [Dataplat.Dbatools.Parameter.DbaInstanceParameter]
        $nativePowerRow.ComputerName.ToString() | Should -Be $nativePowerComputer
        $nativePowerRow.InstanceId | Should -Be $nativePowerActive[0].InstanceID.Split("{")[1].Split("}")[0]
        $nativePowerRow.PowerPlan | Should -Be $nativePowerActive[0].ElementName
        $nativePowerRow.Credential | Should -BeNullOrEmpty
        $nativePowerRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be @("ComputerName", "PowerPlan")
    }

    It "lists the provider's plans in order including every inactive plan" {
        $nativePowerListed = @(Get-DbaPowerPlan -ComputerName $nativePowerComputer -List -EnableException)
        $nativePowerListed.Count | Should -Be $nativePowerExpected.Count
        for ($nativePowerIndex = 0; $nativePowerIndex -lt $nativePowerExpected.Count; $nativePowerIndex++) {
            $nativePowerListedRow = $nativePowerListed[$nativePowerIndex]
            @($nativePowerListedRow.PSObject.Properties.Name) | Should -Be @("ComputerName", "InstanceId", "PowerPlan", "IsActive", "Credential")
            $nativePowerListedRow.InstanceId | Should -Be $nativePowerExpected[$nativePowerIndex].InstanceID.Split("{")[1].Split("}")[0]
            $nativePowerListedRow.PowerPlan | Should -Be $nativePowerExpected[$nativePowerIndex].ElementName
            $nativePowerListedRow.IsActive | Should -Be $nativePowerExpected[$nativePowerIndex].IsActive
            $nativePowerListedRow.IsActive | Should -BeOfType [bool]
            $nativePowerListedRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be @("ComputerName", "PowerPlan", "IsActive")
        }
    }

    It "keeps List and EnableException false switches inactive" -Tag "NativeChecklist:switch-false" {
        $nativePowerFalse = @(Get-DbaPowerPlan -ComputerName $nativePowerComputer -List:$false -EnableException:$false)
        $nativePowerFalse.Count | Should -Be 1
        $nativePowerFalse[0].PowerPlan | Should -Be $nativePowerActive[0].ElementName
        $nativePowerFalse[0].PSObject.Properties["IsActive"] | Should -BeNullOrEmpty
    }

    It "keeps every bound and piped input in order including repeated computers" -Tag "NativeChecklist:pipeline-multiple" {
        $nativePowerInputs = @($nativePowerComputer, "tcp:$nativePowerComputer,1433", $nativePowerComputer)
        $nativePowerBound = @(Get-DbaPowerPlan -ComputerName $nativePowerInputs)
        $nativePowerPiped = @($nativePowerInputs | Get-DbaPowerPlan)
        $nativePowerBound.Count | Should -Be 3
        $nativePowerPiped.Count | Should -Be 3
        for ($nativePowerInputIndex = 0; $nativePowerInputIndex -lt 3; $nativePowerInputIndex++) {
            $nativePowerInput = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $nativePowerInputs[$nativePowerInputIndex]
            $nativePowerBound[$nativePowerInputIndex].ComputerName.ToString() | Should -Be $nativePowerInput.ToString()
            $nativePowerPiped[$nativePowerInputIndex].ComputerName.ToString() | Should -Be $nativePowerInput.ToString()
            $nativePowerBound[$nativePowerInputIndex].PowerPlan | Should -Be $nativePowerActive[0].ElementName
            $nativePowerPiped[$nativePowerInputIndex].PowerPlan | Should -Be $nativePowerActive[0].ElementName
        }
    }

    It "accepts an explicitly null Windows credential" {
        $nativePowerNullCredential = @(Get-DbaPowerPlan -ComputerName $nativePowerComputer -Credential $null -EnableException)
        $nativePowerNullCredential.Count | Should -Be 1
        $nativePowerNullCredential[0].PowerPlan | Should -Be $nativePowerActive[0].ElementName
        $nativePowerNullCredential[0].Credential | Should -BeNullOrEmpty
    }

    It "reads decorated computer inputs when network resolution is bypassed" {
        $nativePowerPreviousBypass = Get-DbatoolsConfigValue -FullName commands.resolve-dbanetworkname.bypass
        try {
            $null = Set-DbatoolsConfig -FullName commands.resolve-dbanetworkname.bypass -Value $true
            $nativePowerBypassInputs = @($nativePowerComputer, "$nativePowerComputer\nativepower", "tcp:$nativePowerComputer,1433")
            $nativePowerBypassRows = @(Get-DbaPowerPlan -ComputerName $nativePowerBypassInputs -EnableException)
            $nativePowerBypassPiped = @($nativePowerBypassInputs | Get-DbaPowerPlan -EnableException)
            $nativePowerBypassRows.Count | Should -Be 3
            $nativePowerBypassPiped.Count | Should -Be 3
            for ($nativePowerBypassIndex = 0; $nativePowerBypassIndex -lt 3; $nativePowerBypassIndex++) {
                $nativePowerBypassInput = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $nativePowerBypassInputs[$nativePowerBypassIndex]
                $nativePowerBypassRows[$nativePowerBypassIndex].ComputerName.ToString() | Should -Be $nativePowerBypassInput.ToString()
                $nativePowerBypassPiped[$nativePowerBypassIndex].ComputerName.ToString() | Should -Be $nativePowerBypassInput.ToString()
                $nativePowerBypassRows[$nativePowerBypassIndex].InstanceId | Should -Be $nativePowerActive[0].InstanceID.Split("{")[1].Split("}")[0]
                $nativePowerBypassPiped[$nativePowerBypassIndex].InstanceId | Should -Be $nativePowerActive[0].InstanceID.Split("{")[1].Split("}")[0]
                $nativePowerBypassRows[$nativePowerBypassIndex].PowerPlan | Should -Be $nativePowerActive[0].ElementName
                $nativePowerBypassPiped[$nativePowerBypassIndex].PowerPlan | Should -Be $nativePowerActive[0].ElementName
            }
        } finally {
            $null = Set-DbatoolsConfig -FullName commands.resolve-dbanetworkname.bypass -Value $nativePowerPreviousBypass
        }
    }

    It "warns for an unresolvable computer and continues to the next input" -Tag "NativeChecklist:multi-instance-failure" {
        $nativePowerWarnings = @()
        $splatNativePowerMissing = @{
            ComputerName    = @($nativePowerMissing, $nativePowerComputer)
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativePowerWarnings"
        }
        $nativePowerSurvivors = @(Get-DbaPowerPlan @splatNativePowerMissing)
        $nativePowerSurvivors.Count | Should -Be 1
        $nativePowerSurvivors[0].PowerPlan | Should -Be $nativePowerActive[0].ElementName
        $nativePowerWarnings.Count | Should -Be 2
        "$($nativePowerWarnings[0])" | Should -BeLike "*Resolve-DbaNetworkName*DNS name $nativePowerMissing not found*"
        "$($nativePowerWarnings[1])" | Should -BeLike "*Get-DbaPowerPlan*Couldn't resolve hostname. Skipping.*"
    }

    It "stops on the command's hostname failure with EnableException" -Tag "NativeChecklist:enable-exception" {
        $nativePowerCaught = $null
        $nativePowerStoppedRows = @()
        $splatNativePowerStop = @{
            ComputerName    = @($nativePowerMissing, $nativePowerComputer)
            WarningAction   = "SilentlyContinue"
            EnableException = $true
        }
        try {
            $nativePowerStoppedRows = @(Get-DbaPowerPlan @splatNativePowerStop)
        } catch {
            $nativePowerCaught = $PSItem
        }
        $nativePowerCaught | Should -Not -BeNullOrEmpty
        $nativePowerCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaPowerPlan*"
        $nativePowerCaught.Exception.Message | Should -BeLike "*Couldn't resolve hostname. Skipping.*"
        $nativePowerStoppedRows.Count | Should -Be 0
    }

    Context "Windows credential" {
        BeforeAll {
            $nativePowerResolved = (Resolve-DbaNetworkName -ComputerName $nativePowerComputer -EnableException).FullComputerName
            $nativePowerCredentialKeys = @($nativePowerComputer.ToLowerInvariant(), $nativePowerResolved.ToLowerInvariant() | Select-Object -Unique)
            $nativePowerUnknownUser = $env:USERDOMAIN + "\nativepower" + [guid]::NewGuid().ToString("N").Substring(0, 8)
            $nativePowerUnknownPassword = ConvertTo-SecureString ([guid]::NewGuid().ToString("N")) -AsPlainText -Force
            $nativePowerUnknownCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $nativePowerUnknownUser, $nativePowerUnknownPassword
        }

        BeforeEach {
            $nativePowerSavedConnections = @{}
            foreach ($nativePowerKey in $nativePowerCredentialKeys) {
                if ([Dataplat.Dbatools.Connection.ConnectionHost]::Connections.ContainsKey($nativePowerKey)) {
                    $nativePowerSavedConnections[$nativePowerKey] = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$nativePowerKey]
                    $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($nativePowerKey)
                }
            }
        }

        AfterEach {
            foreach ($nativePowerRestoreKey in $nativePowerCredentialKeys) {
                $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($nativePowerRestoreKey)
                if ($nativePowerSavedConnections.ContainsKey($nativePowerRestoreKey)) {
                    [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$nativePowerRestoreKey] = $nativePowerSavedConnections[$nativePowerRestoreKey]
                }
            }
        }

        It "does not return the caller's power plans when the supplied credential is refused" {
            $nativePowerCredentialWarnings = @()
            $splatNativePowerCredential = @{
                ComputerName    = $nativePowerComputer
                Credential      = $nativePowerUnknownCredential
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativePowerCredentialWarnings"
            }
            $nativePowerCredentialRows = @(Get-DbaPowerPlan @splatNativePowerCredential)
            $nativePowerCredentialRows.Count | Should -Be 0
            ($nativePowerCredentialWarnings -join " ") | Should -BeLike "*Get-DbaPowerPlan*Can't get Power Plan Info for $nativePowerComputer.*"
        }
    }
}
