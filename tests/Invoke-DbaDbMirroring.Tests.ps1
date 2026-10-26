#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbMirroring",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Primary",
                "PrimarySqlCredential",
                "Mirror",
                "MirrorSqlCredential",
                "Witness",
                "WitnessSqlCredential",
                "Database",
                "EndpointEncryption",
                "EncryptionAlgorithm",
                "SharedPath",
                "InputObject",
                "UseLastBackup",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $dbName = "dbatoolsci_mirroring"
        $endpointName = "dbatoolsci_MirroringEndpoint"

        # Create the objects.
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name $dbName
        $null = New-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy1 -Name $endpointName -Type DatabaseMirroring -Port 5022 -Owner sa
        $null = New-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy2 -Name $endpointName -Type DatabaseMirroring -Port 5023 -Owner sa

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDbMirror -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $dbName
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $dbName
        $null = Remove-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -EndPoint $endpointName

        # Seeding the mirror leaves the full backup and the log backup in the shared folder, and every
        # test file that runs afterwards then reports them as leftovers of its own.
        Get-ChildItem -Path $TestConfig.Temp -Filter "$dbName*" | Remove-Item -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "returns success" {
        $splatMirroring = @{
            Primary    = $TestConfig.InstanceCopy1
            Mirror     = $TestConfig.InstanceCopy2
            Database   = $dbName
            Force      = $true
            SharedPath = $TestConfig.Temp
        }
        $results = Invoke-DbaDbMirroring @splatMirroring -WarningVariable WarnVar
        $WarnVar | Should -BeNullOrEmpty
        $results.Status | Should -Be "Success"
    }

    Context "When the pipeline is stopped" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. The pipeline is stopped as soon as the first
            # mirroring record arrives, which is what Ctrl+C does. WhatIf keeps the instances unchanged. The
            # runspace imports the manifest: an import of the psm1 without a command line skips the type data.
            $splatStopMirroring = @{
                Primary    = $TestConfig.InstanceCopy1
                Mirror     = $TestConfig.InstanceCopy2
                Database   = $dbName
                SharedPath = $TestConfig.Temp
                WhatIf     = $true
            }
            if ($TestConfig.SqlCred) {
                $splatStopMirroring.PrimarySqlCredential = $TestConfig.SqlCred
                $splatStopMirroring.MirrorSqlCredential = $TestConfig.SqlCred
            }
            $stopRunspace = [runspacefactory]::CreateRunspace()
            $stopRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $stopRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $stopShell = [powershell]::Create()
            $stopShell.Runspace = $stopRunspace
            $null = $stopShell.AddCommand("Invoke-DbaDbMirroring").AddParameters($splatStopMirroring)
            $stopAsync = $stopShell.BeginInvoke()
            $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not ($stopShell.Streams.Progress | Where-Object Activity -eq "Setting up mirroring") -and -not $stopAsync.IsCompleted -and $stopWatch.Elapsed.TotalSeconds -lt 60) {
                Start-Sleep -Milliseconds 10
            }
            $stopShell.Stop()
            $stopState = $stopShell.InvocationStateInfo.State
            $stopRecords = @($stopShell.Streams.Progress)
            $stopShell.Dispose()
            $stopRunspace.Dispose()
        }

        It "Was stopped while it was running" {
            $stopState | Should -Be "Stopped"
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $stopRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $stopRecords | Where-Object Activity -eq "Setting up mirroring" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}