#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Stop-DbaExternalProcess",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException",
                "ProcessId"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceRestart -Property ComputerName

        # Setup xp_cmdshell to create external processes for testing
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceRestart -Query "
        -- To allow advanced options to be changed.
        EXECUTE sp_configure 'show advanced options', 1;
        GO
        -- To update the currently configured value for advanced options.
        RECONFIGURE;
        GO
        -- To enable the feature.
        EXECUTE sp_configure 'xp_cmdshell', 1;
        GO
        -- To update the currently configured value for this feature.
        RECONFIGURE;
        GO"

        # Create sql file with code to start an external process
        $sqlFile = "$($TestConfig.Temp)\sleep.sql"
        Set-Content -Path $sqlFile -Value "xp_cmdshell 'powershell -command ""sleep 5""'"

        # Run sql file to start external process
        Start-Process -FilePath sqlcmd -ArgumentList "-S $($TestConfig.InstanceRestart) -i $sqlFile" -NoNewWindow -RedirectStandardOutput null

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        try {
            # Cleanup: Disable xp_cmdshell for security
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceRestart -Query "
            EXECUTE sp_configure 'xp_cmdshell', 0;
            GO
            RECONFIGURE;
            GO
            EXECUTE sp_configure 'show advanced options', 0;
            GO
            RECONFIGURE;
            GO"

            # Restart the SQL Service to ensure we can remove the temporary file.
            $null = Restart-DbaService -ComputerName $TestConfig.InstanceRestart -Type Engine -Force
            Remove-Item -Path $sqlFile
        } finally {
            # A failed or aborted restart above leaves the shared instance stopped,
            # stranding every later suite that targets it. Restore must run even when
            # the cleanup itself throws, and must never throw on its own.
            try {
                $splatGetEngine = @{
                    ComputerName    = $TestConfig.InstanceRestart
                    Type            = "Engine"
                    EnableException = $false
                    WarningAction   = "SilentlyContinue"
                }
                $stoppedEngine = Get-DbaService @splatGetEngine | Where-Object State -ne "Running"
                if ($stoppedEngine) {
                    $splatStartEngine = @{
                        EnableException = $false
                        WarningAction   = "SilentlyContinue"
                    }
                    $null = $stoppedEngine | Start-DbaService @splatStartEngine
                }
            } catch {
                Write-Warning "Fixture restoration failed: $PSItem"
            } finally {
                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }
        }
    }

    Context "Can stop an external process" {
        It "returns results" {
            1..10 | ForEach-Object {
                $results = Get-DbaExternalProcess -ComputerName $computerName | Stop-DbaExternalProcess
                if ($results) { break }
                Start-Sleep -Milliseconds 500
            }
            $results.ComputerName | Should -Be $computerName
            $results.Name | Should -Be "cmd.exe"
            $results.ProcessId | Should -Not -BeNullOrEmpty
            $results.Status | Should -Be "Stopped"
        }
    }
}