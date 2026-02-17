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
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "EXECUTE sp_configure 'show advanced options', 1"
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "RECONFIGURE"
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "EXECUTE sp_configure 'xp_cmdshell', 1"
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "RECONFIGURE"

        # Run xp_cmdshell in a background runspace to start an external process on the SQL instance
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()
        $powerShell = [powershell]::Create()
        $powerShell.Runspace = $runspace
        $null = $powerShell.AddScript({
            param($instance)
            Import-Module C:\github\dbatools\dbatools.psm1
            Set-DbatoolsInsecureConnection
            Invoke-DbaQuery -SqlInstance $instance -Query "xp_cmdshell 'ping -n 120 127.0.0.1'" -QueryTimeout 180
        }).AddArgument($TestConfig.InstanceSingle)
        $runspaceHandle = $powerShell.BeginInvoke()

        # Wait for the external process to start
        Start-Sleep -Seconds 10

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up the background runspace
        if ($null -ne $powerShell) {
            $powerShell.Stop()
            $powerShell.Dispose()
        }
        if ($null -ne $runspace) {
            $runspace.Close()
            $runspace.Dispose()
        }

        # Disable xp_cmdshell after tests (disable xp_cmdshell before disabling advanced options)
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "EXECUTE sp_configure 'xp_cmdshell', 0" -ErrorAction SilentlyContinue
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "RECONFIGURE" -ErrorAction SilentlyContinue
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "EXECUTE sp_configure 'show advanced options', 0" -ErrorAction SilentlyContinue
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "RECONFIGURE" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Can stop an external process" {
        It "returns results" {
            $results = Get-DbaExternalProcess -ComputerName $computerName | Select-Object -First 1 | Stop-DbaExternalProcess -OutVariable "global:dbatoolsciOutput"
            $results.ComputerName | Should -Be $computerName
            $results.Name | Should -Be "cmd.exe"
            $results.ProcessId | Should -Not -BeNullOrEmpty
            $results.Status | Should -Be "Stopped"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "ProcessId",
                "Name",
                "Status"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
