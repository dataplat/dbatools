#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaExternalProcess",
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

        $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceSingle -Property ComputerName

        # Setup xp_cmdshell to create external processes for testing
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

        # Cleanup: Disable xp_cmdshell for security
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

    Context "Can get an external process" {
        It "returns a process" {
            Start-Sleep -Seconds 1
            $results = Get-DbaExternalProcess -ComputerName $computerName | Where-Object Name -eq "cmd.exe"
            Start-Sleep -Seconds 5
            $results.ComputerName | Should -Be $computerName
            $results.Name | Should -Be "cmd.exe"
            $results.ProcessId | Should -Not -Be $null
        }
    }
}