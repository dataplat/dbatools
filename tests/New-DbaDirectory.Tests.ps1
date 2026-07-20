#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDirectory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Path",
                "SqlCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # save the prior EnableException default and restore it in finally, so a setup failure never
        # leaves the forced value enabled for later describes.
        $priorEnableException = $PSDefaultParameterValues["*-Dba*:EnableException"]
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            # New-DbaDirectory creates the folder on the SQL Server machine via xp_create_subdir,
            # using the SQL service account. The instance backup directory is writable by that
            # account, so new subfolders under it are a safe target. Test-DbaPath is the command's
            # own existence check.
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $baseDir = $server.BackupDirectory
            $random = Get-Random
            $happyDir = "$baseDir\dbatoolsci_nd_happy_$random"
            $existDir = "$baseDir\dbatoolsci_nd_exist_$random"
            $whatIfDir = "$baseDir\dbatoolsci_nd_whatif_$random"
            # a path whose name contains a single apostrophe, to exercise the command's SQL-literal
            # escaping ($Path.Replace(quote, doubled-quote)). [char]39 supplies the apostrophe without
            # putting a forbidden single quote in the test source.
            $q = [char]39
            $quoteDir = "$baseDir\dbatoolsci_nd_q${q}uote_$random"

            # These directories are created on the SQL Server HOST and there is no Remove-DbaDirectory
            # to delete them there. A local instance cleans up directly; a REMOTE instance (the
            # canonical lab shape - the gate seat is not the SQL host) cleans up over the admin
            # share, reachable on the lab. Only when NEITHER path can delete does the suite skip,
            # so a genuinely unreachable host never leaves an uncleanable leak - and the gate
            # actually exercises the characterization instead of skipping everything.
            $isLocal = $server.ComputerName -eq $env:COMPUTERNAME
            # An already-UNC BackupDirectory (\\server\share\...) is directly reachable - remapping
            # it through the admin-share form would mangle it into \\host\\\server\share. Only a
            # drive-letter path needs the S:\backups\x -> \\host\S$\backups\x conversion.
            $baseDirIsUnc = $baseDir.StartsWith("\\")
            if ($baseDirIsUnc) {
                $uncBase = $baseDir
            } else {
                $uncBase = "\\$($server.ComputerName)\$($baseDir -replace ([regex]::Escape(":")), [char]36)"
            }
            $canClean = $isLocal -or (Test-Path -LiteralPath $uncBase)

            # maps a server-side path to the path this seat deletes/verifies it at
            $script:ResolveHostPath = {
                param($serverPath)
                if ($isLocal -or $serverPath.StartsWith("\\")) { return $serverPath }
                return "\\$($server.ComputerName)\$($serverPath -replace ([regex]::Escape(":")), [char]36)"
            }

            if ($canClean) {
                # pre-create the "already exists" target through the command itself so the exists-guard
                # test has a real server-side directory.
                $splatPre = @{
                    SqlInstance = $TestConfig.InstanceSingle
                    Path        = $existDir
                    Confirm     = $false
                }
                $null = New-DbaDirectory @splatPre
            }
        } finally {
            if ($null -ne $priorEnableException) {
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $priorEnableException
            } else {
                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }
        }
    }

    AfterAll {
        # These folders live on the SQL Server host - delete at the resolved local/UNC path.
        # -LiteralPath avoids treating a server path containing [ ] as a wildcard. Failures are
        # NOT suppressed: a fixture this suite created but cannot delete is a leak that must
        # surface, so remove with -ErrorAction Stop and assert absence afterwards.
        if ($canClean) {
            foreach ($dir in $happyDir, $existDir, $whatIfDir, $quoteDir) {
                if (-not $dir) { continue }
                $hostPath = & $script:ResolveHostPath $dir
                if (Test-Path -LiteralPath $hostPath) {
                    Remove-Item -LiteralPath $hostPath -Recurse -Force -ErrorAction Stop
                }
                if (Test-Path -LiteralPath $hostPath) {
                    throw "fixture leak: $hostPath survived cleanup"
                }
            }
        }
    }

    Context "Creating a directory" {
        It "Creates a new directory and reports Created true" {
            if (-not $canClean) { Set-ItResult -Skipped -Because "New-DbaDirectory creates server-side folders with no removal API; skipped when neither local nor admin-share cleanup can reach the host"; return }
            $splatNew = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $happyDir
                Confirm         = $false
                EnableException = $true
            }
            $result = @(New-DbaDirectory @splatNew)
            $result.Count | Should -Be 1
            $created = $result[0]
            $created | Should -BeOfType System.Management.Automation.PSCustomObject
            $created.Path | Should -Be $happyDir
            $created.Created | Should -BeTrue
            # Server column carries the targeted instance
            "$($created.Server)" | Should -Be "$($TestConfig.InstanceSingle)"
            foreach ($prop in "Server", "Path", "Created") {
                $created.PSObject.Properties.Name | Should -Contain $prop
            }
            # the directory really exists on the instance now
            $splatVerify = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $happyDir
                EnableException = $true
            }
            Test-DbaPath @splatVerify | Should -BeTrue
        }

        It "Doubles a single quote in the path for the SQL literal and creates the real directory" {
            if (-not $canClean) { Set-ItResult -Skipped -Because "server-side folder with no removal API; skipped when no cleanup path reaches the host"; return }
            $splatQuote = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $quoteDir
                Confirm         = $false
                EnableException = $true
            }
            $result = @(New-DbaDirectory @splatQuote)
            $result.Count | Should -Be 1
            # the returned Path is the SQL-escaped form (apostrophe doubled), mirroring the source
            $result[0].Path | Should -Be $quoteDir.Replace("$q", "$q$q")
            $result[0].Created | Should -BeTrue
            # the ACTUAL directory on disk has the single apostrophe (SQL un-doubles the literal).
            # Test-DbaPath does not escape apostrophes in its own existence query, so verify at the
            # resolved local/UNC host path instead (the context is gated to a cleanable host).
            Test-Path -LiteralPath (& $script:ResolveHostPath $quoteDir) | Should -BeTrue
        }

        It "Warns and emits nothing when the path already exists" {
            if (-not $canClean) { Set-ItResult -Skipped -Because "server-side folder with no removal API; skipped when no cleanup path reaches the host"; return }
            $splatExists = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $existDir
                Confirm         = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = New-DbaDirectory @splatExists
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 1
            $warn[0] | Should -Match ([regex]::Escape("$existDir already exists"))
            # the guard must not delete the existing directory - it still exists afterward
            $splatVerifyExists = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $existDir
                EnableException = $true
            }
            Test-DbaPath @splatVerifyExists | Should -BeTrue
        }

        It "Creates nothing under -WhatIf" {
            if (-not $canClean) { Set-ItResult -Skipped -Because "server-side folder with no removal API; skipped when no cleanup path reaches the host"; return }
            # EnableException surfaces a real failure (e.g. a bad connection) so the no-output +
            # not-created assertions cannot pass vacuously on a soft failure.
            $splatWhatIf = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $whatIfDir
                WhatIf          = $true
                EnableException = $true
            }
            $result = New-DbaDirectory @splatWhatIf
            $result | Should -BeNullOrEmpty
            # ShouldProcess was declined, so the directory was never created
            $splatVerifyWhatIf = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $whatIfDir
                EnableException = $true
            }
            Test-DbaPath @splatVerifyWhatIf | Should -BeFalse
        }
    }
}