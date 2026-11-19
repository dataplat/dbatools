#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Disable-DbaAgHadr",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: azure-sqldb N/A -- The command changes the instance's Always On setting through SQL WMI and restarts Windows services; Azure SQL Database has no SQL WMI, service or Always On configuration a user manages (Microsoft Learn, "Features comparison: Azure SQL Database and Azure SQL Managed Instance": availability is built in for every database; "T-SQL differences": Always On syntax is managed by SQL Database).
# NativeChecklist: sql2005 N/A -- The command opens no SQL Server connection: it reads and changes the HADR setting through SQL WMI and restarts services through Win32_Service.
# NativeChecklist: sql-login N/A -- The pinned function declares no -SqlCredential and opens no SQL Server connection; -Credential is a Windows credential for SQL WMI.
Describe "Disable-DbaAgHadr native" -Tag IntegrationTests {
    BeforeAll {
        $hadrInstance = $TestConfig.InstanceHadr
        $hadrParameter = [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$hadrInstance
        $missingHost = "dbatoolsci-nohost-$(Get-Random)"
        # A host name that does not resolve, with an instance name no computer has: the pinned helper falls
        # back to the computer the tests run on for such a name (correction unresolved-name-local-computer),
        # so no test may name an instance that could exist there.
        $missingInstance = "$missingHost\NATIVEPROBE"

        # The configured HADR setting, read through the same SQL WMI provider the command uses.
        function Get-NativeHadrSetting {
            if (-not ("Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer" -as [type])) {
                $smoFolder = Split-Path -Path ([Microsoft.SqlServer.Management.Smo.Server].Assembly.Location)
                Add-Type -Path (Join-Path -Path $smoFolder -ChildPath "Microsoft.SqlServer.SqlWmiManagement.dll")
            }
            $wmi = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer -ArgumentList $hadrParameter.ComputerName
            $wmi.Services[$hadrParameter.InstanceName].IsHadrEnabled
        }

        # When the engine last started; it changes only when the command restarts it. Waits for an engine
        # that is still starting.
        function Get-NativeStartTime {
            $deadline = (Get-Date).AddSeconds(120)
            while ($true) {
                try {
                    return (Invoke-DbaQuery -SqlInstance $hadrInstance -Query "SELECT sqlserver_start_time FROM sys.dm_os_sys_info" -EnableException).sqlserver_start_time
                } catch {
                    if ((Get-Date) -gt $deadline) {
                        throw
                    }
                    Start-Sleep -Seconds 5
                }
            }
        }

        # Puts HADR back on: a setting change alone while the engine still runs with HADR, a forced restart
        # otherwise, and the Agent running again whatever happened in between.
        function Restore-NativeHadr {
            $null = Get-NativeStartTime
            if ((Get-DbaAgHadr -SqlInstance $hadrInstance -EnableException).IsHadrEnabled) {
                $null = Enable-DbaAgHadr -SqlInstance $hadrInstance -Confirm:$false -EnableException -WarningAction SilentlyContinue
            } else {
                $null = Enable-DbaAgHadr -SqlInstance $hadrInstance -Force -EnableException
            }
            $stoppedAgent = Get-DbaService -SqlInstance $hadrInstance -Type Agent | Where-Object State -ne "Running"
            if ($stoppedAgent) {
                $null = $stoppedAgent | Start-DbaService
            }
        }
    }

    AfterAll {
        Restore-NativeHadr
    }

    Context "-WhatIf" -Tag NativeChecklist:whatif-confirm {
        It "changes neither the setting nor the engine under -WhatIf, even with -Force" {
            $settingBefore = Get-NativeHadrSetting
            $startBefore = Get-NativeStartTime
            $null = Disable-DbaAgHadr -SqlInstance $hadrInstance -Force -WhatIf -WarningAction SilentlyContinue
            Get-NativeHadrSetting | Should -Be $settingBefore
            Get-NativeStartTime | Should -Be $startBefore
        }
    }

    Context "-Force passed as false" -Tag NativeChecklist:switch-false {
        AfterEach {
            Restore-NativeHadr
        }

        It "changes the setting without restarting the engine when -Force is false" {
            $startBefore = Get-NativeStartTime
            $result = Disable-DbaAgHadr -SqlInstance $hadrInstance -Force:$false -Confirm:$false -EnableException:$false -WarningVariable forceWarnings -WarningAction SilentlyContinue
            $result.IsHadrEnabled | Should -BeFalse
            $result.SqlInstance | Should -Be $hadrParameter.FullName
            Get-NativeHadrSetting | Should -BeFalse
            Get-NativeStartTime | Should -Be $startBefore
            ($forceWarnings -join "`n") | Should -Match ([regex]::Escape("You must restart the SQL Server for it to take effect."))
        }
    }

    Context "Pipeline input" -Tag NativeChecklist:pipeline-multiple {
        AfterEach {
            Restore-NativeHadr
        }

        It "disables the setting for every piped instance" {
            $startBefore = Get-NativeStartTime
            $results = @($hadrInstance, $hadrInstance | Disable-DbaAgHadr -Confirm:$false -WarningAction SilentlyContinue)
            $results.Count | Should -Be 2
            ($results.SqlInstance -join ",") | Should -Be (@($hadrParameter.FullName, $hadrParameter.FullName) -join ",")
            ($results.ComputerName -join ",") | Should -Be (@($hadrParameter.ComputerName, $hadrParameter.ComputerName) -join ",")
            ($results.InstanceName -join ",") | Should -Be (@($hadrParameter.InstanceName, $hadrParameter.InstanceName) -join ",")
            Get-NativeHadrSetting | Should -BeFalse
            Get-NativeStartTime | Should -Be $startBefore
        }
    }

    Context "One of several instances fails" -Tag NativeChecklist:multi-instance-failure {
        AfterEach {
            Restore-NativeHadr
        }

        It "warns for the unreachable computer and still disables the reachable instance" {
            $results = @(Disable-DbaAgHadr -SqlInstance $missingInstance, $hadrInstance -Confirm:$false -WarningVariable failureWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            $results[0].SqlInstance | Should -Be $hadrParameter.FullName
            ($failureWarnings -join "`n") | Should -Match ([regex]::Escape("Failure on $missingInstance | This may be because"))
            Get-NativeHadrSetting | Should -BeFalse
        }
    }

    Context "EnableException" -Tag NativeChecklist:enable-exception {
        # Get-WmiHadr's own failure only warns: the pinned helper never sets EnableException, so the throw
        # comes from the setting change, as in the pinned function.
        It "throws for an unreachable computer with -EnableException" {
            { Disable-DbaAgHadr -SqlInstance $missingInstance -Confirm:$false -EnableException -WarningAction SilentlyContinue } | Should -Throw "*Failure on $missingInstance | This may be because*"
        }

        It "warns and returns nothing for an unreachable computer without -EnableException" {
            $result = Disable-DbaAgHadr -SqlInstance $missingInstance -Confirm:$false -WarningVariable failureWarnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($failureWarnings -join "`n") | Should -Match ([regex]::Escape("Failure on $missingInstance | This may be because"))
        }
    }

    Context "Computer name that does not resolve" {
        # Correction unresolved-name-local-computer: the pinned Invoke-ManagedComputerCommand builds
        # ManagedComputer from Resolve-DbaNetworkName's missing address, $null, which is the computer the
        # command runs on, so it read and changed SQL WMI there. The port asks the named computer, which
        # cannot be reached; a local attempt never fails with "The RPC server is unavailable". -WhatIf keeps
        # this test read-only even where the defect is present.
        It "reads SQL WMI on the named computer, never on this one, when the name does not resolve" {
            $result = Disable-DbaAgHadr -SqlInstance $missingInstance -WhatIf -WarningVariable resolveWarnings -WarningAction SilentlyContinue
            $warningText = $resolveWarnings -join "`n"
            $warningText | Should -Match ([regex]::Escape("DNS name $missingHost not found | "))
            $warningText | Should -Match ([regex]::Escape("Failure connecting to $missingHost | Failed to connect to SQL WMI on $missingHost. Local connection attempt failed with: The RPC server is unavailable."))
            $result.ComputerName | Should -BeNullOrEmpty
            $result.IsHadrEnabled | Should -BeFalse
        }
    }
}
