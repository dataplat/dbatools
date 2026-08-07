#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaFilestream",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "FileStreamLevel",
                "ShareName",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeDiscovery {
        # Level 1 is T-SQL access and needs nothing from Windows. Level 2 adds Win32 file I/O
        # streaming, which SQL Server exposes through a Windows file share - so level 2 depends on
        # the host being able to serve a share at all, which is the Server service (LanmanServer).
        # That is an OS prerequisite, not a SQL Server one: FILESTREAM is a configuration setting,
        # not an installable feature, so nothing about how the instance was installed decides this.
        #
        # This is the split seen on ci-azure on 2026-08-06, where level 1 passed and level 2 failed
        # on all three attempts. Probe that prerequisite rather than the CI provider: the old
        # -Skip:$env:APPVEYOR stopped describing anything once AppVeyor went away, because
        # tests\gha.shim.ps1 still sets the variable, so it skipped on every runner unconditionally.
        #
        # If the probe cannot answer, run the test. A skip has to be earned, and a probe that fails
        # for its own reasons must not hide a regression in the command.
        $filestreamHost = "$($TestConfig.InstanceRestart)".Split("\")[0].Split(",")[0]
        if ($filestreamHost -in ".", "localhost", "(local)", "") {
            $filestreamHost = $env:COMPUTERNAME
        }

        try {
            $splatServerService = @{
                ClassName   = "Win32_Service"
                ErrorAction = "Stop"
            }
            if ($filestreamHost -ne $env:COMPUTERNAME) {
                $splatServerService["ComputerName"] = $filestreamHost
            }
            $serverService = Get-CimInstance @splatServerService | Where-Object Name -eq "LanmanServer"
            $canServeFileShare = $serverService.State -eq "Running"
        } catch {
            $canServeFileShare = $true
        }
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Disable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -Force

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When changing FileStream Level" {
        It "Should change the FileStream Level to 1" {
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 1 -Force

            $results.InstanceAccessLevel | Should -Be 1
            $results.ServiceAccessLevel | Should -Be 1
        }

        It "Should change the FileStream Level to 2" -Skip:(-not $canServeFileShare) {
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 2 -ShareName TestShare -Force

            # A bare "Expected 2, but got 1" says nothing about which of the two levels stalled or
            # what the instance ended up with, which cost a full CI round trip on 2026-08-06.
            # Report the state the instance actually reached so the next failure explains itself.
            $reportedState = (Get-DbaFilestream -SqlInstance $TestConfig.InstanceRestart | Out-String).Trim()

            $results.InstanceAccessLevel | Should -Be 2 -Because "the instance reported $reportedState"
            $results.ServiceAccessLevel | Should -Be 2 -Because "the instance reported $reportedState"
            $results.ServiceShareName | Should -Be TestShare -Because "the instance reported $reportedState"
        }

        It "Should warn if using ShareName with FileStreamLevel 1" {
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 1 -ShareName Test -WarningAction SilentlyContinue

            $WarnVar | Should -BeLike '*Filestream must be at least level 2 when using ShareName*'
            $results | Should -BeNullOrEmpty
        }
    }
}