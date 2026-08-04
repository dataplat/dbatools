#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPageFileSetting",
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

Describe $CommandName -Tag IntegrationTests -Skip:(-not $env:appveyor) {
    # Skip on local tests as we don't get any results on SQL Server 2022

    BeforeDiscovery {
        # The CI runners boot from an ephemeral OS disk and have no page file: the OS
        # disk occupies the resource disk, so the D:\pagefile.sys the image asks for
        # never materialises. Get-DbaPageFileSetting emits nothing when Win32_PageFile
        # is empty, which is correct behaviour, not a regression. Probe the CIM classes
        # directly rather than the command, so a genuine Get-DbaPageFileSetting bug
        # still fails this test instead of skipping it.
        #
        # Only a probe that SUCCEEDED and came back empty is grounds to skip. A probe that
        # errored proves nothing: treating an access denial, a broken WMI service or a bad
        # query as "no page file" would hand back a green skip we have not earned. That is
        # exactly the "never skip on a result that a bug could also produce" trap in
        # tests/CLAUDE.md, so a failed probe leaves the assertion running instead.
        $pageFileProbed = $false
        $hasPageFile = $false
        try {
            $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            $pageFiles = @(Get-CimInstance -ClassName Win32_PageFile -ErrorAction Stop)
            $hasPageFile = [bool]$computerSystem.AutomaticManagedPagefile -or $pageFiles.Count -gt 0
            $pageFileProbed = $true
        } catch {
            Write-Warning "Page file probe failed, running the assertion anyway: $PSItem"
        }
    }

    Context "Gets PageFile Settings" -Skip:($pageFileProbed -and -not $hasPageFile) {
        It "Gets results" {
            $results = Get-DbaPageFileSetting -ComputerName $env:ComputerName
            $results | Should -Not -BeNullOrEmpty
        }
    }
}