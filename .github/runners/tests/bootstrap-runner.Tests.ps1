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

    # the runner install is lifted the same way; its tests stand in for the listener
    foreach ($installFunctionName in "Get-RunnerPackageVersion", "Install-RunnerPackage") {
        $installFunction = $bootstrapAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $installFunctionName
            }, $true)
        if (-not $installFunction) {
            throw "$installFunctionName is missing from bootstrap-runner.ps1; the runner install depends on it"
        }
        . ([scriptblock]::Create($installFunction[0].Extent.Text))
    }

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

    It "sets an account lockout threshold of five or lower before the runner takes its job" {
        # the Set-DbaLogin unlock test fails exactly five logons and expects the login to be
        # locked afterwards; without a threshold on the runner it never is (#10529)
        $bootstrapText = Get-Content -Path $script:BootstrapPath -Raw
        $bootstrapText | Should -Match "net accounts /lockoutthreshold:(\d+)"
        $threshold = [int][regex]::Match($bootstrapText, "net accounts /lockoutthreshold:(\d+)").Groups[1].Value
        $threshold | Should -BeGreaterThan 0
        $threshold | Should -BeLessOrEqual 5
        $bootstrapText.IndexOf("net accounts /lockoutthreshold:") | Should -BeLessThan $bootstrapText.IndexOf("& .\config.cmd")
    }

    It "installs the pinned runner version, hash checked, before the marker and config.cmd" {
        # GitHub stops handing jobs to a runner once its runtime support ends, and the image
        # staged 2.335.1, which ran out on 2026-09-24. Every VM then registered, exited as
        # deprecated, probed SPENT and was replaced without serving a job (2026-11-15).
        $bootstrapText = Get-Content -Path $script:BootstrapPath -Raw
        $versionMatch = [regex]::Match($bootstrapText, "\`$runnerVersion = `"(\d+\.\d+\.\d+)`"")
        $versionMatch.Success | Should -BeTrue
        $bootstrapText | Should -Match "\`$runnerSha256 = `"[0-9a-f]{64}`""
        $bootstrapText | Should -Match "Sha256\s+= \`$runnerSha256"
        $installIndex = $bootstrapText.IndexOf("Install-RunnerPackage @splatRunnerPackage")
        $markerIndex = $bootstrapText.IndexOf(".bootstrapped-once`" -Value")
        $installIndex | Should -BeGreaterThan 0
        $installIndex | Should -BeLessThan $markerIndex
        $installIndex | Should -BeLessThan $bootstrapText.IndexOf("& .\config.cmd")
    }

    It "stages the same runner version in the golden image as the bootstrap installs" {
        # with the two in step the bootstrap finds the version already staged and skips the
        # download; a rebuilt image that lags behind still works, it just downloads again
        $bootstrapText = Get-Content -Path $script:BootstrapPath -Raw
        $runnerVersion = [regex]::Match($bootstrapText, "\`$runnerVersion = `"(\d+\.\d+\.\d+)`"").Groups[1].Value
        $runnerSha256 = [regex]::Match($bootstrapText, "\`$runnerSha256 = `"([0-9a-f]{64})`"").Groups[1].Value
        $imageStepPath = Join-Path -Path $PSScriptRoot -ChildPath "../image-scripts/step1-tools.ps1"
        $imageStepText = Get-Content -Path $imageStepPath -Raw
        $imageStepText | Should -Match "\`$runnerVersion = `"$([regex]::Escape($runnerVersion))`""
        $imageStepText | Should -Match "\`$runnerSha256 = `"$runnerSha256`""
        $imageStepText | Should -Match ([regex]::Escape("releases/download/v`$runnerVersion/actions-runner-win-x64-`$runnerVersion.zip"))
    }

    It "refuses a golden image runner download whose hash is not the pinned one" {
        # the image bakes the runner into every VM, so a tampered or truncated download would
        # reach the whole fleet; the image build stops instead
        $imageStepPath = Join-Path -Path $PSScriptRoot -ChildPath "../image-scripts/step1-tools.ps1"
        $imageStepText = Get-Content -Path $imageStepPath -Raw
        $downloadIndex = $imageStepText.IndexOf("DownloadFile(`$runnerUrl")
        $hashIndex = $imageStepText.IndexOf("-ne `$runnerSha256")
        $extractIndex = $imageStepText.IndexOf("ExtractToDirectory(`$runnerZip")
        $downloadIndex | Should -BeGreaterThan 0
        $hashIndex | Should -BeGreaterThan $downloadIndex
        $hashIndex | Should -BeLessThan $extractIndex
    }
}

Describe "Install-RunnerPackage" {
    BeforeAll {
        $script:InstallRoots = @()

        # a stand-in listener: bin\Runner.Listener.exe holds the version it reports, as text
        Mock Get-RunnerPackageVersion {
            $listenerPath = Join-Path -Path $RunnerRoot -ChildPath "bin\Runner.Listener.exe"
            if (Test-Path -Path $listenerPath) {
                (Get-Content -Path $listenerPath -Raw).Trim()
            }
        }

        function New-InstallTestFolder {
            param(
                [hashtable]$File = @{ }
            )

            $root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "runner-install-test-$([System.Guid]::NewGuid().ToString("N"))"
            $null = [System.IO.Directory]::CreateDirectory($root)
            foreach ($relativePath in $File.Keys) {
                $filePath = Join-Path -Path $root -ChildPath $relativePath
                $null = [System.IO.Directory]::CreateDirectory((Split-Path -Path $filePath -Parent))
                Set-Content -Path $filePath -Value $File[$relativePath]
            }
            $script:InstallRoots += $root
            $root
        }

        function New-InstallTestPackage {
            param(
                [Parameter(Mandatory)]
                [string]$ListenerVersion,
                [switch]$WithoutExternals
            )

            $packageFiles = @{
                "bin\Runner.Listener.exe"   = $ListenerVersion
                "bin\Runner.Worker.dll"     = "worker $ListenerVersion"
                "externals\node20\node.exe" = "node 20"
                "config.cmd"                = "config $ListenerVersion"
                "run.cmd"                   = "run $ListenerVersion"
            }
            if ($WithoutExternals) {
                $packageFiles.Remove("externals\node20\node.exe")
            }
            $contentRoot = New-InstallTestFolder -File $packageFiles
            $packagePath = Join-Path -Path (New-InstallTestFolder) -ChildPath "actions-runner.zip"
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($contentRoot, $packagePath)
            [PSCustomObject]@{
                Url    = ([System.Uri]$packagePath).AbsoluteUri
                Sha256 = (Get-FileHash -Path $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }

        function Get-OldRunnerFile {
            @{
                "bin\Runner.Listener.exe"   = "2.335.1"
                "bin\Runner.Old.dll"        = "only in 2.335.1"
                "externals\node16\node.exe" = "node 16"
                "config.cmd"                = "config 2.335.1"
                "run.cmd"                   = "run 2.335.1"
            }
        }

        $script:CurrentPackage = New-InstallTestPackage -ListenerVersion "2.338.2"
        $script:MissingPackageUrl = ([System.Uri](Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "runner-install-test-missing-$([System.Guid]::NewGuid().ToString("N")).zip")).AbsoluteUri
    }

    AfterAll {
        foreach ($root in $script:InstallRoots) {
            $splatRemoveInstallRoot = @{
                Path        = $root
                Recurse     = $true
                Force       = $true
                ErrorAction = "SilentlyContinue"
            }
            Remove-Item @splatRemoveInstallRoot
        }
    }

    It "replaces an older staged runner and leaves no file of it behind" {
        $root = New-InstallTestFolder -File (Get-OldRunnerFile)
        $splatInstall = @{
            RunnerRoot = $root
            Version    = "2.338.2"
            Sha256     = $script:CurrentPackage.Sha256
            PackageUrl = $script:CurrentPackage.Url
        }
        $installOutput = @(Install-RunnerPackage @splatInstall)
        $installOutput[-1] | Should -Be "runner 2.338.2 installed"
        Get-Content -Path (Join-Path -Path $root -ChildPath "bin\Runner.Listener.exe") | Should -Be "2.338.2"
        Join-Path -Path $root -ChildPath "bin\Runner.Old.dll" | Should -Not -Exist
        Join-Path -Path $root -ChildPath "externals\node16" | Should -Not -Exist
        Join-Path -Path $root -ChildPath "externals\node20\node.exe" | Should -Exist
        Get-Content -Path (Join-Path -Path $root -ChildPath "config.cmd") | Should -Be "config 2.338.2"
        @(Get-ChildItem -Path $root -Filter ".runner-package-*") | Should -HaveCount 0
    }

    It "leaves a runner that already reports the version alone and downloads nothing" {
        $currentFiles = Get-OldRunnerFile
        $currentFiles["bin\Runner.Listener.exe"] = "2.338.2"
        $root = New-InstallTestFolder -File $currentFiles
        $splatInstall = @{
            RunnerRoot = $root
            Version    = "2.338.2"
            Sha256     = $script:CurrentPackage.Sha256
            PackageUrl = $script:MissingPackageUrl
        }
        Install-RunnerPackage @splatInstall | Should -Be "runner 2.338.2 is staged"
        Get-Content -Path (Join-Path -Path $root -ChildPath "config.cmd") | Should -Be "config 2.335.1"
        @(Get-ChildItem -Path $root -Filter ".runner-package-*") | Should -HaveCount 0
    }

    It "refuses a package whose SHA256 differs and keeps the staged runner" {
        $root = New-InstallTestFolder -File (Get-OldRunnerFile)
        $wrongSha256 = "0" * 64
        $splatInstall = @{
            RunnerRoot = $root
            Version    = "2.338.2"
            Sha256     = $wrongSha256
            PackageUrl = $script:CurrentPackage.Url
        }
        { Install-RunnerPackage @splatInstall } | Should -Throw "*has SHA256 $($script:CurrentPackage.Sha256), expected $wrongSha256"
        Get-Content -Path (Join-Path -Path $root -ChildPath "bin\Runner.Listener.exe") | Should -Be "2.335.1"
        Join-Path -Path $root -ChildPath "bin\Runner.Old.dll" | Should -Exist
        @(Get-ChildItem -Path $root -Filter ".runner-package-*") | Should -HaveCount 0
    }

    It "fails a download that never arrives and keeps the staged runner" {
        $root = New-InstallTestFolder -File (Get-OldRunnerFile)
        $splatInstall = @{
            RunnerRoot = $root
            Version    = "2.338.2"
            Sha256     = $script:CurrentPackage.Sha256
            PackageUrl = $script:MissingPackageUrl
        }
        { Install-RunnerPackage @splatInstall } | Should -Throw
        Get-Content -Path (Join-Path -Path $root -ChildPath "bin\Runner.Listener.exe") | Should -Be "2.335.1"
        @(Get-ChildItem -Path $root -Filter ".runner-package-*") | Should -HaveCount 0
    }

    It "fails an install whose listener reports another version" {
        $otherPackage = New-InstallTestPackage -ListenerVersion "2.338.1"
        $root = New-InstallTestFolder -File (Get-OldRunnerFile)
        $splatInstall = @{
            RunnerRoot = $root
            Version    = "2.338.2"
            Sha256     = $otherPackage.Sha256
            PackageUrl = $otherPackage.Url
        }
        { Install-RunnerPackage @splatInstall } | Should -Throw "runner reports version 2.338.1 after the install, expected 2.338.2"
    }

    It "finishes an install an earlier pass cut off before bin arrived" {
        # the state an install leaves when it dies between removing bin and moving the new
        # one in: no listener, old externals, new root files, a staging folder left behind
        $cutOffFiles = @{
            "externals\node16\node.exe"                                         = "node 16"
            "config.cmd"                                                        = "config 2.338.2"
            ".runner-package-0123456789abcdef\unpacked\bin\Runner.Listener.exe" = "2.338.2"
        }
        $root = New-InstallTestFolder -File $cutOffFiles
        $splatInstall = @{
            RunnerRoot = $root
            Version    = "2.338.2"
            Sha256     = $script:CurrentPackage.Sha256
            PackageUrl = $script:CurrentPackage.Url
        }
        $installOutput = @(Install-RunnerPackage @splatInstall)
        $installOutput[-1] | Should -Be "runner 2.338.2 installed"
        Get-Content -Path (Join-Path -Path $root -ChildPath "bin\Runner.Listener.exe") | Should -Be "2.338.2"
        Join-Path -Path $root -ChildPath "externals\node16" | Should -Not -Exist
        Join-Path -Path $root -ChildPath "externals\node20\node.exe" | Should -Exist
        @(Get-ChildItem -Path $root -Filter ".runner-package-*") | Should -HaveCount 0
    }

    It "leaves no listener behind when the package cannot be moved in whole" {
        # bin is the last folder to arrive, so an install that fails before it leaves the VM
        # probing as not installed and the next pass installs again, rather than one that
        # registers a 2.338.2 listener without its externals
        $incompletePackage = New-InstallTestPackage -ListenerVersion "2.338.2" -WithoutExternals
        $root = New-InstallTestFolder -File (Get-OldRunnerFile)
        $splatInstall = @{
            RunnerRoot = $root
            Version    = "2.338.2"
            Sha256     = $incompletePackage.Sha256
            PackageUrl = $incompletePackage.Url
        }
        { Install-RunnerPackage @splatInstall } | Should -Throw
        Join-Path -Path $root -ChildPath "bin\Runner.Listener.exe" | Should -Not -Exist
        Get-RunnerPackageVersion -RunnerRoot $root | Should -BeNullOrEmpty
        @(Get-ChildItem -Path $root -Filter ".runner-package-*") | Should -HaveCount 0
    }
}
