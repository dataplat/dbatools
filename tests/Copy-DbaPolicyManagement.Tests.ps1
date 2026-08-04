#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaPolicyManagement",
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
                "Policy",
                "ExcludePolicy",
                "Condition",
                "ExcludeCondition",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Object set selection" {
        It "copies only object sets required by selected policies" {
            $executedQueries = InModuleScope dbatools {
                function New-MockScriptedPbmObject {
                    param(
                        [string]$Name,
                        [string]$ScriptText,
                        [string]$ObjectSet,
                        [string]$PolicyCategory
                    )

                    $mockPbmObject = [PSCustomObject]@{
                        Name           = $Name
                        IsSystemObject = $false
                        ObjectSet      = $ObjectSet
                        PolicyCategory = $PolicyCategory
                        ScriptText     = $ScriptText
                    }

                    $mockPbmObject | Add-Member -Force -MemberType ScriptMethod -Name ScriptCreate -Value {
                        $scriptResult = [PSCustomObject]@{
                            ScriptText = $this.ScriptText
                        }
                        $scriptResult | Add-Member -Force -MemberType ScriptMethod -Name GetScript -Value { $this.ScriptText }
                        $scriptResult
                    }

                    $mockPbmObject
                }

                function New-MockPbmServer {
                    param(
                        [string]$Name
                    )

                    $mockServer = [PSCustomObject]@{
                        Name              = $Name
                        ConnectionContext = [PSCustomObject]@{
                            SqlConnectionObject = "$Name-Connection"
                        }
                    }

                    $mockServer | Add-Member -Force -MemberType ScriptMethod -Name Query -Value {
                        param($Sql)
                        $script:executedQueries += $Sql.Trim()
                        $null
                    }

                    $mockServer
                }

                function Add-PbmLibrary { }
                function Test-FunctionInterrupt { $false }
                function Write-Message { }
                function Select-DefaultView {
                    param(
                        [Parameter(ValueFromPipeline)]
                        $InputObject,
                        [Parameter(ValueFromRemainingArguments)]
                        $RemainingArguments
                    )

                    process {
                        $InputObject
                    }
                }
                function Connect-DbaInstance {
                    param($SqlInstance)

                    if ($SqlInstance -eq "source1") {
                        $script:mockSourceServer
                    } else {
                        $script:mockDestinationServer
                    }
                }
                function New-Object {
                    param(
                        [string]$TypeName,
                        [Parameter(ValueFromRemainingArguments)]
                        $ArgumentList
                    )

                    if ($TypeName -eq "Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection") {
                        return [PSCustomObject]@{ }
                    }

                    if ($TypeName -eq "Microsoft.SqlServer.Management.DMF.PolicyStore") {
                        $script:policyStoreCallCount++
                        if ($script:policyStoreCallCount -eq 1) {
                            return $script:mockSourceStore
                        }
                        return $script:mockDestinationStore
                    }

                    Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
                }

                $script:executedQueries = @()
                $script:policyStoreCallCount = 0
                $script:mockSourceServer = New-MockPbmServer -Name "source1"
                $script:mockDestinationServer = New-MockPbmServer -Name "destination1"

                $mockDestinationPolicies = @{ }
                $mockDestinationPolicies | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }

                $mockDestinationConditions = @{ }
                $mockDestinationConditions | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }

                $mockDestinationObjectSets = @{ }
                $mockDestinationObjectSets | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }

                $mockDestinationPolicyCategories = @{ }
                $mockDestinationPolicyCategories | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }

                $script:mockSourceStore = [PSCustomObject]@{
                    Policies         = @(
                        (New-MockScriptedPbmObject -Name "PolicyA" -ObjectSet "ObjectSetA" -PolicyCategory "PolicyCategoryA" -ScriptText "CREATE POLICY [PolicyA]"),
                        (New-MockScriptedPbmObject -Name "PolicyB" -ObjectSet "ObjectSetB" -PolicyCategory "PolicyCategoryB" -ScriptText "CREATE POLICY [PolicyB]")
                    )
                    Conditions       = @()
                    ObjectSets       = @(
                        (New-MockScriptedPbmObject -Name "ObjectSetA" -ScriptText "CREATE OBJECT SET [ObjectSetA]"),
                        (New-MockScriptedPbmObject -Name "ObjectSetB" -ScriptText "CREATE OBJECT SET [ObjectSetB]")
                    )
                    PolicyCategories = @()
                }

                $script:mockDestinationStore = [PSCustomObject]@{
                    Policies         = $mockDestinationPolicies
                    Conditions       = $mockDestinationConditions
                    ObjectSets       = $mockDestinationObjectSets
                    PolicyCategories = $mockDestinationPolicyCategories
                }

                $null = Copy-DbaPolicyManagement -Source "source1" -Destination "destination1" -Policy "PolicyA"

                $script:executedQueries
            }

            $executedQueries | Should -Contain "CREATE OBJECT SET [ObjectSetA]"
            $executedQueries | Should -Contain "CREATE POLICY [PolicyA]"
            $executedQueries | Should -Not -Contain "CREATE OBJECT SET [ObjectSetB]"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: the actual copy migrates Policy-Based Management policies, conditions, and
    # object sets from a source to a destination instance, which needs a live Source+Destination
    # pair - that behavior leg is DEFERRED-TO-COPYPAIR (the standing Source+Destination gate pair
    # for the Copy-* family, per the coordinator ruling 2026-07-18; the mocked UnitTests above
    # already pin the policy/objectset copy dispatch). What IS characterizable deterministically is
    # the platform guard the source runs first: on a non-Windows host the command refuses to run.
    # Per the coordinator ruling this is pinned by flipping the module-scope $script:isWindows state
    # (InModuleScope), never by mocking Connect-DbaInstance (the documented mock-coupling latent-red
    # class); the flip is restored in a finally so it cannot leak into other tests.
    Context "Guarding on a non-Windows platform" {
        It "Warns and returns nothing when the host is not Windows" {
            InModuleScope dbatools {
                # [char]39 supplies the apostrophe the source message contains (the contraction of
                # "we are") without a literal apostrophe in the test source
                $q = [char]39
                $originalIsWindows = $script:isWindows
                try {
                    $script:isWindows = $false
                    $splatNonWindows = @{
                        Source          = "dbatoolsci-src"
                        Destination     = "dbatoolsci-dst"
                        WarningVariable = "warn"
                        WarningAction   = "SilentlyContinue"
                        WhatIf          = $true
                    }
                    $result = @(Copy-DbaPolicyManagement @splatNonWindows)
                    $result.Count | Should -Be 0
                    $warn.Count | Should -Be 1

                    # strip the bracketed [timestamp]/[function] prefix added by Write-Message
                    $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
                    $payload | Should -Be "Copy-DbaPolicyManagement does not support Linux - we${q}re still waiting for the Core SMOs from Microsoft"
                } finally {
                    $script:isWindows = $originalIsWindows
                }
            }
        }
    }

    Context "Suppressing the copy under -WhatIf" {
        # -WhatIf on a Copy-* command can only be asserted as an ABSENCE, and a command that did
        # nothing at all satisfies an absence assertion just as well as one that was correctly
        # suppressed. So both arms run off the same fixture: whatever the -WhatIf arm claims is
        # only worth reading because the control arm proves the fixture reaches the create.
        It "Issues no create statement under -WhatIf, and does without it" {
            $armResults = InModuleScope dbatools {
                function New-MockScriptedPbmObject {
                    param(
                        [string]$Name,
                        [string]$ScriptText,
                        [string]$ObjectSet,
                        [string]$PolicyCategory
                    )

                    $mockPbmObject = [PSCustomObject]@{
                        Name           = $Name
                        IsSystemObject = $false
                        ObjectSet      = $ObjectSet
                        PolicyCategory = $PolicyCategory
                        ScriptText     = $ScriptText
                    }

                    $mockPbmObject | Add-Member -Force -MemberType ScriptMethod -Name ScriptCreate -Value {
                        $scriptResult = [PSCustomObject]@{
                            ScriptText = $this.ScriptText
                        }
                        $scriptResult | Add-Member -Force -MemberType ScriptMethod -Name GetScript -Value { $this.ScriptText }
                        $scriptResult
                    }

                    $mockPbmObject
                }

                function New-MockPbmServer {
                    param(
                        [string]$Name
                    )

                    $mockServer = [PSCustomObject]@{
                        Name              = $Name
                        ConnectionContext = [PSCustomObject]@{
                            SqlConnectionObject = "$Name-Connection"
                        }
                    }

                    $mockServer | Add-Member -Force -MemberType ScriptMethod -Name Query -Value {
                        param($Sql)
                        $script:executedQueries += $Sql.Trim()
                        $null
                    }

                    $mockServer
                }

                function Add-PbmLibrary { }
                function Test-FunctionInterrupt { $false }
                function Write-Message { }
                function Select-DefaultView {
                    param(
                        [Parameter(ValueFromPipeline)]
                        $InputObject,
                        [Parameter(ValueFromRemainingArguments)]
                        $RemainingArguments
                    )

                    process {
                        $InputObject
                    }
                }
                function Connect-DbaInstance {
                    param($SqlInstance)

                    if ($SqlInstance -eq "whatifsource") {
                        $script:mockSourceServer
                    } else {
                        $script:mockDestinationServer
                    }
                }
                function New-Object {
                    param(
                        [string]$TypeName,
                        [Parameter(ValueFromRemainingArguments)]
                        $ArgumentList
                    )

                    if ($TypeName -eq "Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection") {
                        return [PSCustomObject]@{ }
                    }

                    if ($TypeName -eq "Microsoft.SqlServer.Management.DMF.PolicyStore") {
                        $script:policyStoreCallCount++
                        if ($script:policyStoreCallCount -eq 1) {
                            return $script:mockSourceStore
                        }
                        return $script:mockDestinationStore
                    }

                    Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
                }

                # Under Invoke-ManualPester the module-scope flag reads empty, which sends the
                # command down its non-Windows refusal branch before it can touch the fixture -
                # and a refusal satisfies the -WhatIf absence assertion perfectly.
                $originalIsWindows = $script:isWindows
                try {
                    $script:isWindows = $true

                    $armQueries = @{ }
                    foreach ($armName in "WhatIf", "Control") {
                        $script:executedQueries = @()
                        $script:policyStoreCallCount = 0
                        $script:mockSourceServer = New-MockPbmServer -Name "whatifsource"
                        $script:mockDestinationServer = New-MockPbmServer -Name "whatifdestination"

                        $mockDestinationPolicies = @{ }
                        $mockDestinationPolicies | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }

                        $mockDestinationConditions = @{ }
                        $mockDestinationConditions | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }

                        $mockDestinationObjectSets = @{ }
                        $mockDestinationObjectSets | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }

                        $mockDestinationPolicyCategories = @{ }
                        $mockDestinationPolicyCategories | Add-Member -Force -MemberType ScriptMethod -Name Refresh -Value { }

                        $script:mockSourceStore = [PSCustomObject]@{
                            Policies         = @(
                                (New-MockScriptedPbmObject -Name "PolicyA" -ObjectSet "ObjectSetA" -PolicyCategory "PolicyCategoryA" -ScriptText "CREATE POLICY [PolicyA]")
                            )
                            Conditions       = @()
                            ObjectSets       = @(
                                (New-MockScriptedPbmObject -Name "ObjectSetA" -ScriptText "CREATE OBJECT SET [ObjectSetA]")
                            )
                            PolicyCategories = @()
                        }

                        $script:mockDestinationStore = [PSCustomObject]@{
                            Policies         = $mockDestinationPolicies
                            Conditions       = $mockDestinationConditions
                            ObjectSets       = $mockDestinationObjectSets
                            PolicyCategories = $mockDestinationPolicyCategories
                        }

                        $splatCopyArm = @{
                            Source      = "whatifsource"
                            Destination = "whatifdestination"
                            Policy      = "PolicyA"
                        }
                        if ($armName -eq "WhatIf") {
                            $splatCopyArm.WhatIf = $true
                        }
                        $null = Copy-DbaPolicyManagement @splatCopyArm

                        $armQueries[$armName] = @($script:executedQueries)
                    }

                    $armQueries
                } finally {
                    $script:isWindows = $originalIsWindows
                }
            }

            $armResults["Control"] | Should -Contain "CREATE POLICY [PolicyA]"
            $armResults["Control"] | Should -Contain "CREATE OBJECT SET [ObjectSetA]"
            @($armResults["WhatIf"]).Count | Should -Be 0
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
            # succeeds silently on a path that already exists and leaves its permissions
            # alone, so the one thing that must not happen is adopting somebody else's
            # directory and executing a script out of it.
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
`$resolved = Get-Command -Name Copy-DbaPolicyManagement -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaPolicyManagement"
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
