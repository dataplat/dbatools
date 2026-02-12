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

        $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceSingle -Property ComputerName

        # Enable xp_cmdshell for test process creation
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "
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
        Start-Process -FilePath sqlcmd -ArgumentList "-S $($TestConfig.InstanceSingle) -i $sqlFile" -NoNewWindow -RedirectStandardOutput null

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Disable xp_cmdshell after tests
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "
        EXECUTE sp_configure 'xp_cmdshell', 0;
        GO
        RECONFIGURE;
        GO
        EXECUTE sp_configure 'show advanced options', 0;
        GO
        RECONFIGURE;
        GO"

        # remove sql file
        Remove-Item -Path $sqlFile

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Can stop an external process" {
        It "returns results" {
            Start-Sleep -Seconds 1
            $results = Get-DbaExternalProcess -ComputerName $computerName | Select-Object -First 1 | Stop-DbaExternalProcess
            Start-Sleep -Seconds 5
            $results.ComputerName | Should -Be $computerName
            $results.Name | Should -Be "cmd.exe"
            $results.ProcessId | Should -Not -BeNullOrEmpty
            $results.Status | Should -Be "Stopped"
        }

        Context "Output validation" {
            It "Returns output of the documented type" {
                if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
                $results | Should -BeOfType [PSCustomObject]
            }

            It "Has the expected properties" {
                if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
                $results.PSObject.Properties.Name | Should -Contain "ComputerName"
                $results.PSObject.Properties.Name | Should -Contain "ProcessId"
                $results.PSObject.Properties.Name | Should -Contain "Name"
                $results.PSObject.Properties.Name | Should -Contain "Status"
            }
        }
    }
}