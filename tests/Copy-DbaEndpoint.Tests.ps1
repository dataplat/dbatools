#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaEndpoint",
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
                "Endpoint",
                "ExcludeEndpoint",
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

        # Explain what needs to be set up for the test:
        # To test copying endpoints, we need to create a test endpoint on the source instance.

        # Set variables. They are available in all the It blocks.
        $endpointName = "dbatoolsci_MirroringEndpoint"
        $endpointPort = 5022

        # Create the objects.
        $splatEndpoint = @{
            SqlInstance     = $TestConfig.InstanceCopy1
            Name            = $endpointName
            Type            = "DatabaseMirroring"
            Port            = $endpointPort
            Owner           = "sa"
            EnableException = $true
        }
        $null = New-DbaEndpoint @splatEndpoint

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy1 -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy2 -Type DatabaseMirroring | Remove-DbaEndpoint

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying endpoints between instances" {
        It "Successfully copies a mirroring endpoint" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Endpoint    = $endpointName
            }
            $results = Copy-DbaEndpoint @splatCopy
            $results.DestinationServer | Should -Be $TestConfig.InstanceCopy2
            $results.Status | Should -Be "Successful"
            $results.Name | Should -Be $endpointName
        }
    }

    Context "When -WhatIf is used" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A Service Broker endpoint rather than a second mirroring one: SQL Server allows only
            # one DATABASE_MIRRORING endpoint per instance, so the Describe-level fixture already
            # holds that slot.
            $brokerName = "dbatoolsci_BrokerWhatIf"
            $splatBroker = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Name        = $brokerName
                Type        = "ServiceBroker"
                Port        = 5023
                Owner       = "sa"
            }
            $null = New-DbaEndpoint @splatBroker

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            foreach ($cleanupInstance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
                $null = Get-DbaEndpoint -SqlInstance $cleanupInstance -Endpoint $brokerName | Remove-DbaEndpoint
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should not create the endpoint on the destination" {
            $splatWhatIf = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Endpoint    = $brokerName
                WhatIf      = $true
            }
            $null = Copy-DbaEndpoint @splatWhatIf
            Get-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy2 -Endpoint $brokerName | Should -BeNullOrEmpty
        }

        It "Should create the endpoint once -WhatIf is dropped" {
            # Without this the leg above would pass just as well against a command that copies
            # nothing at all.
            $splatReal = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Endpoint    = $brokerName
            }
            $results = Copy-DbaEndpoint @splatReal
            $results.Status | Should -Be "Successful"
            Get-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy2 -Endpoint $brokerName | Should -Not -BeNullOrEmpty
        }
    }

    Context "When the endpoint already exists on the destination" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $existingName = "dbatoolsci_BrokerExisting"
            $splatExisting = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Name        = $existingName
                Type        = "ServiceBroker"
                Port        = 5024
                Owner       = "sa"
            }
            $null = New-DbaEndpoint @splatExisting

            $splatSeed = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Endpoint    = $existingName
            }
            $null = Copy-DbaEndpoint @splatSeed

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            foreach ($cleanupInstance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
                $null = Get-DbaEndpoint -SqlInstance $cleanupInstance -Endpoint $existingName | Remove-DbaEndpoint
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should report Skipped and leave the destination endpoint alone" {
            $existingBefore = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy2 -Endpoint $existingName
            $splatSkip = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Endpoint    = $existingName
            }
            $results = Copy-DbaEndpoint @splatSkip
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "Already exists on destination"
            $existingAfter = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy2 -Endpoint $existingName
            $existingAfter.Name | Should -Be $existingBefore.Name
        }

        It "Should drop and recreate the endpoint when -Force is used" {
            $splatForce = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Endpoint    = $existingName
                Force       = $true
            }
            $results = Copy-DbaEndpoint @splatForce
            $results.Status | Should -Be "Successful"
            Get-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy2 -Endpoint $existingName | Should -Not -BeNullOrEmpty
        }
    }

    Context "When one call spans more than one destination" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $multiName = "dbatoolsci_BrokerMulti"
            $splatMultiSource = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Name        = $multiName
                Type        = "ServiceBroker"
                Port        = 5025
                Owner       = "sa"
            }
            $null = New-DbaEndpoint @splatMultiSource

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            foreach ($cleanupInstance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
                $null = Get-DbaEndpoint -SqlInstance $cleanupInstance -Endpoint $multiName | Remove-DbaEndpoint
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should emit one result per destination, each with its own status" {
            # The source instance is deliberately one of the destinations: the endpoint is already
            # there, so the two results must differ in status as well as in server. A port that
            # handled only the first destination would return one object and still look green
            # against a Count-free assertion.
            $splatBoth = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2, $TestConfig.InstanceCopy1
                Endpoint    = $multiName
            }
            $results = Copy-DbaEndpoint @splatBoth
            $results.Count | Should -Be 2
            @($results.DestinationServer | Sort-Object -Unique).Count | Should -Be 2
            ($results | Where-Object DestinationServer -eq $TestConfig.InstanceCopy2).Status | Should -Be "Successful"
            ($results | Where-Object DestinationServer -eq $TestConfig.InstanceCopy1).Status | Should -Be "Skipped"
        }
    }

    Context "When a server cannot be reached" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $unreachableName = "dbatoolsci_BrokerUnreachable"
            $splatUnreachableSource = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Name        = $unreachableName
                Type        = "ServiceBroker"
                Port        = 5026
                Owner       = "sa"
            }
            $null = New-DbaEndpoint @splatUnreachableSource

            $previousConnectTimeout = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            Set-DbatoolsConfig -FullName sql.connection.timeout -Value 1

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Set-DbatoolsConfig -FullName sql.connection.timeout -Value $previousConnectTimeout
            foreach ($cleanupInstance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
                $null = Get-DbaEndpoint -SqlInstance $cleanupInstance -Endpoint $unreachableName | Remove-DbaEndpoint
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should warn on the unreachable destination and still copy to the reachable one" {
            # Stop-Function -Continue binds to the destination loop, so the second destination has to
            # be reached anyway. It also proves the warning stream survives the hop: a swallowed 3>&1
            # leaves -WarningVariable empty.
            $connectWarning = $null
            $splatMixed = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceUnreachable, $TestConfig.InstanceCopy2
                Endpoint        = $unreachableName
                WarningVariable = "connectWarning"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $results = Copy-DbaEndpoint @splatMixed
            $connectWarning | Should -Not -BeNullOrEmpty
            ($results | Where-Object DestinationServer -eq $TestConfig.InstanceCopy2).Status | Should -Be "Successful"
        }

        It "Should reach no destination at all when the source cannot be connected" {
            # The source connect failure latches Test-FunctionInterrupt, and the guard ahead of the
            # destination loop is what turns that latch into "nothing happened". Without it the loop
            # would run against a null source server and produce results.
            $sourceWarning = $null
            $splatDeadSource = @{
                Source          = $TestConfig.InstanceUnreachable
                Destination     = $TestConfig.InstanceCopy2
                Endpoint        = $unreachableName
                WarningVariable = "sourceWarning"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $results = Copy-DbaEndpoint @splatDeadSource
            $sourceWarning | Should -Not -BeNullOrEmpty
            $results | Should -BeNullOrEmpty
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
            # with CreateNew rather than written over whatever is at the path.
            $probeDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-resolve-$([guid]::NewGuid().ToString("N"))"
            # A GUID makes this unreachable in practice, but every create-directory API below
            # succeeds silently on a path that already exists and leaves its permissions alone, so
            # the one thing that must not happen is adopting somebody else's directory and
            # executing a script out of it.
            if (Test-Path -LiteralPath $probeDirectory) {
                throw "$probeDirectory already exists - this run will not execute a script out of a directory it did not create"
            }
            # Only a directory this block actually created may be deleted in AfterAll. Without the
            # flag the throw above hands the cleanup a path it just refused to touch.
            $probeDirectoryCreated = $false
            $probeDirectoryInfo = New-Object System.IO.DirectoryInfo($probeDirectory)
            if ([System.Environment]::OSVersion.Platform -eq "Win32NT") {
                # The running identity owns it, not Administrators: only an elevated run can hand
                # ownership to a group it is not in, and a descriptor that omits the creator locks
                # the creator out of the directory it just made.
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
                # edition: .NET Framework has DirectoryInfo.Create(DirectorySecurity), .NET moved
                # it out to FileSystemAclExtensions. Probing for the overload rather than the
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
                # everywhere else, so the mode carries the same job there. mkdir rather than a .NET
                # call, for the exclusivity: every managed create-directory API succeeds silently
                # on a directory that already exists and leaves its permissions alone.
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
`$resolved = Get-Command -Name Copy-DbaEndpoint -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaEndpoint"
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
