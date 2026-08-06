#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaStartupProcedure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Procedure",
                "ExcludeProcedure",
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
        $procAlpha = "dbatoolsci_startup_alpha"
        $procBeta  = "dbatoolsci_startup_beta"
        $procGamma = "dbatoolsci_startup_gamma"
        $procPlain = "dbatoolsci_plain_delta"
        $allProcs  = @($procAlpha, $procBeta, $procGamma, $procPlain)

        # Each body carries its own marker so a definition read off the destination identifies
        # which source procedure it actually came from.
        function Get-DestinationProcedureState {
            param($ProcedureName)

            $splatState = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "master"
                Query       = "SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.$ProcedureName')) AS Definition, (SELECT is_auto_executed FROM sys.procedures WHERE name = '$ProcedureName' AND schema_id = SCHEMA_ID('dbo')) AS IsAutoExecuted"
            }
            Invoke-DbaQuery @splatState
        }

        # Clean both ends first - a leftover startup procedure from an interrupted run would make
        # the -WhatIf absence assertion pass for the wrong reason.
        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            foreach ($proc in $allProcs) {
                Invoke-DbaQuery -SqlInstance $instance -Database "master" -Query "IF OBJECT_ID('dbo.$proc') IS NOT NULL DROP PROCEDURE dbo.$proc"
            }
        }

        # Create the objects.
        foreach ($proc in $procAlpha, $procBeta, $procGamma, $procPlain) {
            $marker = "$proc-v1"
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Database "master" -Query "CREATE PROCEDURE dbo.$proc AS SELECT '$marker' AS Marker"
        }

        # Only the first three are flagged for startup - the fourth proves the ExecIsStartup filter.
        foreach ($proc in $procAlpha, $procBeta, $procGamma) {
            $splatStartup = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = "master"
                Query       = "EXEC sp_procoption @ProcName = N'$proc', @OptionName = 'startup', @OptionValue = 'on'"
            }
            Invoke-DbaQuery @splatStartup
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects. A startup procedure left behind would execute on every
        # instance restart, so this drops from both ends whether or not the copy legs ran.
        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            foreach ($proc in $allProcs) {
                Invoke-DbaQuery -SqlInstance $instance -Database "master" -Query "IF OBJECT_ID('dbo.$proc') IS NOT NULL DROP PROCEDURE dbo.$proc"
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When previewing with -WhatIf" {
        BeforeAll {
            $splatWhatIf = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Procedure   = $procAlpha
                WhatIf      = $true
            }
            $whatIfResults = Copy-DbaStartupProcedure @splatWhatIf

            $whatIfState = Get-DestinationProcedureState -ProcedureName $procAlpha
        }

        It "Should return no result objects" {
            $whatIfResults | Should -BeNullOrEmpty
        }

        It "Should not create the procedure on the destination" {
            $whatIfState.Definition | Should -BeNullOrEmpty
        }
    }

    Context "When copying multiple startup procedures in one call" {
        BeforeAll {
            $splatMulti = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Procedure   = @($procAlpha, $procBeta)
            }
            $multiResults = Copy-DbaStartupProcedure @splatMulti

            $alphaState = Get-DestinationProcedureState -ProcedureName $procAlpha
            $betaState  = Get-DestinationProcedureState -ProcedureName $procBeta
        }

        It "Should report both procedures as Successful" {
            $statuses = $multiResults | Where-Object Name -in $procAlpha, $procBeta | Select-Object -ExpandProperty Status
            $statuses.Count | Should -Be 2
            $statuses | Should -Not -Contain "Failed"
            ($statuses | Sort-Object -Unique) | Should -Be "Successful"
        }

        It "Should land each procedure with its own body, not the first record's" {
            $alphaState.Definition | Should -BeLike "*$procAlpha-v1*"
            $betaState.Definition | Should -BeLike "*$procBeta-v1*"
        }

        It "Should flag both procedures for startup on the destination" {
            $alphaState.IsAutoExecuted | Should -Be 1
            $betaState.IsAutoExecuted | Should -Be 1
        }
    }

    Context "When the procedure already exists on the destination" {
        BeforeAll {
            $splatSkip = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Procedure   = $procAlpha
            }
            $skipResults = Copy-DbaStartupProcedure @splatSkip

            $skipState = Get-DestinationProcedureState -ProcedureName $procAlpha
        }

        It "Should report the procedure as Skipped" {
            $skipped = $skipResults | Where-Object Name -eq $procAlpha
            $skipped.Status | Should -Be "Skipped"
            $skipped.Notes | Should -Be "Already exists on destination"
        }

        It "Should leave the destination body untouched" {
            $skipState.Definition | Should -BeLike "*$procAlpha-v1*"
        }
    }

    Context "When -Force overwrites an existing startup procedure" {
        BeforeAll {
            $splatAlter = @{
                SqlInstance     = $TestConfig.InstanceCopy1
                Database        = "master"
                Query           = "ALTER PROCEDURE dbo.$procAlpha AS SELECT '$procAlpha-v2' AS Marker"
                EnableException = $true
            }
            Invoke-DbaQuery @splatAlter

            $splatForce = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Procedure   = $procAlpha
                Force       = $true
            }
            $forceResults = Copy-DbaStartupProcedure @splatForce

            $forceState = Get-DestinationProcedureState -ProcedureName $procAlpha
        }

        It "Should report the procedure as Successful" {
            $forced = $forceResults | Where-Object Name -eq $procAlpha
            $forced.Status | Should -Be "Successful"
        }

        It "Should replace the destination body with the newer source body" {
            $forceState.Definition | Should -BeLike "*$procAlpha-v2*"
        }

        It "Should still flag the recreated procedure for startup" {
            $forceState.IsAutoExecuted | Should -Be 1
        }
    }

    Context "When -WhatIf reports the operations it would perform" {
        BeforeAll {
            # ShouldProcess writes its WhatIf line straight to the host and is not reachable by
            # stream redirection on either edition, so a transcript is the only in-process capture.
            $transcriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "dbatoolsci_startupproc_whatif_$([guid]::NewGuid().ToString("N")).log"

            Start-Transcript -Path $transcriptPath | Out-Null
            try {
                # Gamma is not on the destination yet, so this reaches the create action; alpha is,
                # so it reaches the already-exists action and, with -Force, the drop-and-recreate one.
                $splatCreateAction = @{
                    Source      = $TestConfig.InstanceCopy1
                    Destination = $TestConfig.InstanceCopy2
                    Procedure   = $procGamma
                    WhatIf      = $true
                }
                $null = Copy-DbaStartupProcedure @splatCreateAction

                $splatExistsAction = @{
                    Source      = $TestConfig.InstanceCopy1
                    Destination = $TestConfig.InstanceCopy2
                    Procedure   = $procAlpha
                    WhatIf      = $true
                }
                $null = Copy-DbaStartupProcedure @splatExistsAction

                $splatForceAction = @{
                    Source      = $TestConfig.InstanceCopy1
                    Destination = $TestConfig.InstanceCopy2
                    Procedure   = $procAlpha
                    Force       = $true
                    WhatIf      = $true
                }
                $null = Copy-DbaStartupProcedure @splatForceAction
            } finally {
                Stop-Transcript | Out-Null
            }

            $whatIfTranscript = Get-Content -Path $transcriptPath -Raw
            Remove-Item -Path $transcriptPath -Force -ErrorAction SilentlyContinue
        }

        It "Should report the create action verbatim" {
            $whatIfTranscript | Should -BeLike "*Creating startup procedure dbo.$procGamma*"
        }

        It "Should report the already-exists action verbatim" {
            $whatIfTranscript | Should -BeLike "*Startup procedure dbo.$procAlpha exists at destination. Use -Force to drop and migrate.*"
        }

        It "Should report the force drop-and-recreate action verbatim" {
            $whatIfTranscript | Should -BeLike "*Dropping startup procedure dbo.$procAlpha and recreating*"
        }
    }

    # This Context doubles as the absence control for the one above: it copies gamma for real and
    # expects Successful, which only holds if the -WhatIf create above did not actually create it.
    Context "When -ExcludeProcedure is used without -Procedure" {
        BeforeAll {
            $splatExclude = @{
                Source           = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                ExcludeProcedure = @($procAlpha, $procBeta)
            }
            $excludeResults = Copy-DbaStartupProcedure @splatExclude

            $gammaState = Get-DestinationProcedureState -ProcedureName $procGamma
            $plainState = Get-DestinationProcedureState -ProcedureName $procPlain
        }

        It "Should copy the procedure that was not excluded" {
            ($excludeResults | Where-Object Name -eq $procGamma).Status | Should -Be "Successful"
            $gammaState.Definition | Should -BeLike "*$procGamma-v1*"
            $gammaState.IsAutoExecuted | Should -Be 1
        }

        It "Should report nothing at all for the excluded procedures" {
            $excludeResults | Where-Object Name -in $procAlpha, $procBeta | Should -BeNullOrEmpty
        }

        It "Should not copy a procedure that is not flagged for startup" {
            $excludeResults | Where-Object Name -eq $procPlain | Should -BeNullOrEmpty
            $plainState.Definition | Should -BeNullOrEmpty
        }
    }

    Context "When resolving the command name in a cold shell" {
        BeforeAll {
            # Every other leg runs in a session that imported dbatools long before Pester started,
            # so none of them can tell the binary cmdlet apart from the retired script function -
            # whichever got there first answers to the name. This leg starts a shell of the same
            # edition that has imported nothing, loads the module the way a consumer does, and asks
            # what the name resolves to. dbatools.psm1 is the import under test on purpose: it is
            # the loader that pulls the satellite in by path, and importing the manifest by name
            # cannot work in a dev tree because the satellites are not on PSModulePath.
            $moduleBase = @(Get-Module -Name dbatools)[0].ModuleBase
            $shellPath = (Get-Process -Id $PID).Path

            # This file is EXECUTED, so where it lives matters as much as what is in it. It goes in
            # a per-invocation directory that only its creator and the machine's administrators can
            # write to, rather than in the shared temp root, under a GUID name, and created below
            # with CreateNew rather than written over whatever is at the path. Closing the write
            # handle before the run is only safe because of the directory: on the shared temp root
            # there is a window between the write and the run in which anyone can substitute the
            # script.
            $probeDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-resolve-$([guid]::NewGuid().ToString("N"))"

            # A GUID makes this unreachable in practice, but every create-directory API below
            # succeeds silently on a path that already exists and leaves its permissions alone, so
            # the one thing that must not happen is adopting somebody else's directory and
            # executing a script out of it.
            if (Test-Path -LiteralPath $probeDirectory) {
                throw "$probeDirectory already exists - this run will not execute a script out of a directory it did not create"
            }

            # Only a directory this block actually created may be deleted in AfterAll. Without the
            # flag the throw above hands the cleanup a path it just refused to touch, and refusing
            # to execute out of somebody else's directory while recursively deleting it is worse
            # than either outcome on its own.
            $probeDirectoryCreated = $false
            $probeDirectoryInfo = New-Object System.IO.DirectoryInfo($probeDirectory)

            if ([System.Environment]::OSVersion.Platform -eq "Win32NT") {
                # The running identity owns it, not Administrators: only an elevated run can hand
                # ownership to a group it is not in, and a descriptor that omits the creator locks
                # the creator out of the directory it just made. Administrators and SYSTEM are on it
                # because they can reach the file whatever this says, so excluding them buys nothing
                # and costs the elevated case.
                $currentSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User
                $administratorsSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
                $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)

                $probeSecurity = New-Object System.Security.AccessControl.DirectorySecurity
                $probeSecurity.SetAccessRuleProtection($true, $false)
                $probeSecurity.SetOwner($currentSid)
                foreach ($trusteeSid in $currentSid, $administratorsSid, $systemSid) {
                    $probeRule = New-Object System.Security.AccessControl.FileSystemAccessRule($trusteeSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
                    $probeSecurity.AddAccessRule($probeRule)
                }

                # Created WITH the descriptor, never created and then secured - the gap between
                # those two calls carries inherited permissions. Which call does it differs by
                # edition: .NET Framework has DirectoryInfo.Create(DirectorySecurity), .NET moved it
                # out to FileSystemAclExtensions, and Directory.CreateDirectory(path, security)
                # exists on neither PowerShell 7 nor v3. Probing for the overload rather than the
                # PSEdition because it is the overload that decides.
                $probeNativeCreate = [System.IO.DirectoryInfo].GetMethod("Create", [Type[]]@([System.Security.AccessControl.DirectorySecurity]))
                if ($probeNativeCreate) {
                    $probeDirectoryInfo.Create($probeSecurity)
                } else {
                    [System.IO.FileSystemAclExtensions]::Create($probeDirectoryInfo, $probeSecurity)
                }
                $probeDirectoryCreated = $true
            } else {
                # DirectorySecurity is Windows-only and throws PlatformNotSupportedException
                # everywhere else, so the mode carries the same job there. The umask cannot: under a
                # permissive one the directory comes out group- or world-writable and the executed
                # script is substitutable.
                # mkdir rather than a .NET call, for the exclusivity: every managed
                # create-directory API succeeds silently on a directory that already exists and
                # leaves that directory's permissions alone, so a pre-created one would be used as
                # is. mkdir without -p fails instead, and -m carries the mode in the same call.
                # It also sidesteps UnixFileMode, which is .NET 7 and absent on PowerShell 7.2/7.3.
                # A non-zero exit is fatal: carrying on would execute a script out of a directory
                # whose permissions are unknown.
                $null = & /bin/mkdir -m 700 $probeDirectory
                if ($LASTEXITCODE -ne 0) {
                    throw "could not create $probeDirectory with owner-only permissions (mkdir exited $LASTEXITCODE)"
                }
                $probeDirectoryCreated = $true
            }

            $probePath = Join-Path -Path $probeDirectory -ChildPath "resolve.ps1"

            # Get-Command -All so a retired function shadowing the cmdlet shows up as a second
            # entry rather than silently winning; the count is what proves it is not there.
            $probeBody = @"
param(`$ModuleBase)
# The module path is an ARGUMENT, not interpolated text: this script is executed, and a
# path carrying a quote or a $ would otherwise close the string and run as code.
Import-Module -Name (Join-Path -Path `$ModuleBase -ChildPath "dbatools.psm1") -DisableNameChecking
`$resolved = Get-Command -Name Copy-DbaStartupProcedure -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaStartupProcedure"
    All         = `$true
    ErrorAction = "SilentlyContinue"
}
`$allResolved = @(Get-Command @splatResolveAll)
`$functionCount = @(`$allResolved | Where-Object { `$PSItem.CommandType -eq "Function" }).Count
`$satelliteLoaded = [bool](Get-Module -Name dbatools.migration)
"RESOLVED|`$(`$resolved.CommandType)|`$(`$resolved.ModuleName)|`$functionCount|`$satelliteLoaded"
"@

            $probeStream = New-Object System.IO.FileStream($probePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            try {
                $probeBytes = [System.Text.Encoding]::UTF8.GetBytes($probeBody)
                $probeStream.Write($probeBytes, 0, $probeBytes.Length)
            } finally {
                $probeStream.Dispose()
            }

            $probeArguments = @("-NoProfile", "-NonInteractive", "-File", $probePath, $moduleBase)
            $probeOutput = & $shellPath @probeArguments 2>&1
            $probeFields = @("$(@($probeOutput | Where-Object { "$PSItem" -like "RESOLVED|*" })[0])" -split "\|")
        }

        AfterAll {
            if ($probeDirectoryCreated) {
                $splatRemoveProbeDirectory = @{
                    Path        = $probeDirectory
                    Recurse     = $true
                    Force       = $true
                    ErrorAction = "SilentlyContinue"
                }
                Remove-Item @splatRemoveProbeDirectory
            }
        }

        It "Should resolve to the binary cmdlet shipped by dbatools.migration" {
            $probeFields[1] | Should -Be "Cmdlet"
            $probeFields[2] | Should -Be "dbatools.migration"
        }

        It "Should load the satellite and leave no retired function shadowing the name" {
            $probeFields[4] | Should -Be "True"
            $probeFields[3] | Should -Be "0"
        }
    }
}
