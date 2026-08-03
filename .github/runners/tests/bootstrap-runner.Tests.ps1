BeforeAll {
    $script:BootstrapPath = Join-Path -Path $PSScriptRoot -ChildPath "../bootstrap-runner.ps1"

    # Lift Get-RunnerVmState out of the script rather than dot-sourcing the file: the
    # bootstrap body reconfigures the firewall, resizes the system partition and runs
    # config.cmd, none of which belong in a unit test.
    $parseErrors = $null
    $parseTokens = $null
    $bootstrapAst = [System.Management.Automation.Language.Parser]::ParseFile($script:BootstrapPath, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors) {
        throw "bootstrap-runner.ps1 does not parse: $($parseErrors[0].Message)"
    }

    $stateFunction = $bootstrapAst.FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq "Get-RunnerVmState"
        }, $true)
    if (-not $stateFunction) {
        throw "Get-RunnerVmState is missing from bootstrap-runner.ps1; the reconcile probe contract depends on it"
    }
    . ([scriptblock]::Create($stateFunction[0].Extent.Text))

    function New-RunnerRoot {
        param(
            [switch]$Bootstrapped,
            [switch]$Configured
        )

        $root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "bootstrap-test-$([System.Guid]::NewGuid().ToString("N"))"
        $null = New-Item -Path $root -ItemType Directory
        if ($Bootstrapped) {
            Set-Content -Path (Join-Path -Path $root -ChildPath ".bootstrapped-once") -Value "2026-08-03T00:00:00.0000000+00:00"
        }
        if ($Configured) {
            Set-Content -Path (Join-Path -Path $root -ChildPath ".runner") -Value "{}"
        }
        $root
    }

    function New-FakeService {
        param(
            [Parameter(Mandatory)]
            [string]$Status
        )

        [PSCustomObject]@{
            Name   = "actions.runner.dataplat-dbatools.testvm"
            Status = $Status
        }
    }
}

Describe "Get-RunnerVmState" {
    BeforeAll {
        $script:CreatedRoots = @()
    }

    AfterAll {
        foreach ($root in $script:CreatedRoots) {
            Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "A VM that has never been bootstrapped" {
        It "reports fresh so the bootstrap proceeds" {
            $root = New-RunnerRoot
            $script:CreatedRoots += $root
            Mock Get-Service { throw "Get-Service must not be consulted before the marker exists" }

            Get-RunnerVmState -RunnerRoot $root | Should -Be "fresh"
        }
    }

    Context "A VM that is still serving its single job" {
        It "reports healthy when the runner is configured and its service is running" {
            $root = New-RunnerRoot -Bootstrapped -Configured
            $script:CreatedRoots += $root
            Mock Get-Service { New-FakeService -Status "Running" }

            Get-RunnerVmState -RunnerRoot $root | Should -Be "healthy"
        }
    }

    Context "A VM that has already served its job" {
        It "reports spent when ephemeral cleanup removed .runner" {
            # the ephemeral runner unregisters itself and deletes .runner after one job
            $root = New-RunnerRoot -Bootstrapped
            $script:CreatedRoots += $root
            Mock Get-Service { }

            Get-RunnerVmState -RunnerRoot $root | Should -Be "spent"
        }

        It "reports spent even when a stopped service is left behind" {
            # .runner deleted but the SCM entry survives; the old .runner-only check would
            # have called this healthy and left the pool silently under strength
            $root = New-RunnerRoot -Bootstrapped
            $script:CreatedRoots += $root
            Mock Get-Service { New-FakeService -Status "Stopped" }

            Get-RunnerVmState -RunnerRoot $root | Should -Be "spent"
        }
    }

    Context "A VM whose bootstrap died mid-configuration" {
        It "reports spent when the service is missing entirely" {
            # marker written, config.cmd never installed the service
            $root = New-RunnerRoot -Bootstrapped -Configured
            $script:CreatedRoots += $root
            Mock Get-Service { }

            Get-RunnerVmState -RunnerRoot $root | Should -Be "spent"
        }

        It "reports spent when the service exists but is not running" {
            $root = New-RunnerRoot -Bootstrapped -Configured
            $script:CreatedRoots += $root
            Mock Get-Service { New-FakeService -Status "Stopped" }

            Get-RunnerVmState -RunnerRoot $root | Should -Be "spent"
        }

        It "reports healthy when one of several runner services is running" {
            $root = New-RunnerRoot -Bootstrapped -Configured
            $script:CreatedRoots += $root
            Mock Get-Service { @((New-FakeService -Status "Stopped"), (New-FakeService -Status "Running")) }

            Get-RunnerVmState -RunnerRoot $root | Should -Be "healthy"
        }
    }
}

Describe "bootstrap-runner.ps1 contract" {
    It "defaults RunnerRoot to the path the golden image stages" {
        $default = (Get-Command Get-RunnerVmState).Parameters["RunnerRoot"].Attributes
        $bootstrapText = Get-Content -Path $script:BootstrapPath -Raw
        $bootstrapText | Should -Match ([regex]::Escape("[string]`$RunnerRoot = `"C:\github-runner`""))
        $default | Should -Not -BeNullOrEmpty
    }

    It "registers the runner as a LocalSystem service and never reboots" {
        $bootstrapText = Get-Content -Path $script:BootstrapPath -Raw
        $bootstrapText | Should -Match ([regex]::Escape("--runasservice"))
        $bootstrapText | Should -Match ([regex]::Escape("NT AUTHORITY\SYSTEM"))
        $bootstrapText | Should -Not -Match "shutdown\.exe"
        $bootstrapText | Should -Not -Match "AutoAdminLogon"
        $bootstrapText | Should -Not -Match "DefaultPassword"
    }

    It "writes the bootstrapped-once marker before invoking config.cmd" {
        # in service mode the runner can take a job the moment config.cmd starts the
        # service, so a bootstrap that dies mid-config must probe as SPENT, not be retried
        $bootstrapText = Get-Content -Path $script:BootstrapPath -Raw
        $markerIndex = $bootstrapText.IndexOf(".bootstrapped-once`" -Value")
        $configIndex = $bootstrapText.IndexOf("& .\config.cmd")
        $markerIndex | Should -BeGreaterThan 0
        $configIndex | Should -BeGreaterThan 0
        $markerIndex | Should -BeLessThan $configIndex
    }
}
