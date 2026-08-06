#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Sync-DbaAvailabilityGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Primary",
                "PrimarySqlCredential",
                "Secondary",
                "SecondarySqlCredential",
                "Credential",
                "AvailabilityGroup",
                "Exclude",
                "Login",
                "ExcludeLogin",
                "Job",
                "ExcludeJob",
                "DisableJobOnDestination",
                "InputObject",
                "ExcludePassword",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Connection behavior" {
        It "Should let Copy-DbaCredential manage dedicated admin connections" {
            InModuleScope "dbatools" {
                # The stand-ins are installed into the module's own command table so the sync body
                # sees them wherever it runs, which means they outlive this block unless they are
                # put back - and a leaked Connect-DbaInstance would silently mock every later leg.
                $functionNames = @(
                    "Connect-DbaInstance",
                    "Copy-DbaCredential",
                    "Test-FunctionInterrupt",
                    "Write-ProgressHelper"
                )
                $originalFunctions = @{ }
                foreach ($functionName in $functionNames) {
                    if (Test-Path "Function:\$functionName") {
                        $originalFunctions[$functionName] = (Get-Item -Path "Function:\$functionName").ScriptBlock
                    }
                }

                try {
                    function Test-FunctionInterrupt { $false }
                    function Write-ProgressHelper { }
                    function Connect-DbaInstance {
                        param(
                            $SqlInstance,
                            $SqlCredential,
                            [switch]$DedicatedAdminConnection
                        )

                        if ($DedicatedAdminConnection) {
                            $script:dacConnections += $SqlInstance.ToString()
                        }

                        [PSCustomObject]@{
                            Name               = $SqlInstance.ToString()
                            DomainInstanceName = $SqlInstance.ToString()
                        }
                    }
                    function Copy-DbaCredential {
                        param(
                            $Source,
                            $Destination,
                            $Credential,
                            [switch]$ExcludePassword,
                            [switch]$Force
                        )

                        $script:copyCredentialCall = [PSCustomObject]@{
                            Source          = $Source
                            Destination     = $Destination
                            Credential      = $Credential
                            ExcludePassword = $ExcludePassword.IsPresent
                        }
                    }

                    $script:dacConnections = @()
                    $script:copyCredentialCall = $null

                    $exclude = @(
                        "AgentAlert",
                        "AgentCategory",
                        "AgentJob",
                        "AgentOperator",
                        "AgentProxy",
                        "AgentSchedule",
                        "CustomErrors",
                        "DatabaseMail",
                        "DatabaseOwner",
                        "LinkedServers",
                        "LoginPermissions",
                        "Logins",
                        "SpConfigure",
                        "SystemTriggers"
                    )
                    $securePassword = ConvertTo-SecureString "Password1!" -AsPlainText -Force
                    $credential = New-Object System.Management.Automation.PSCredential("contoso\syncuser", $securePassword)

                    $null = Sync-DbaAvailabilityGroup -Primary "sql1" -Secondary "sql2" -Credential $credential -Exclude $exclude

                    $script:dacConnections | Should -BeNullOrEmpty
                    $script:copyCredentialCall.Credential.UserName | Should -Be "contoso\syncuser"
                    $script:copyCredentialCall.ExcludePassword | Should -BeFalse
                } finally {
                    foreach ($functionName in $functionNames) {
                        if ($originalFunctions.ContainsKey($functionName)) {
                            Set-Item -Path "Function:\$functionName" -Value $originalFunctions[$functionName]
                        } else {
                            Remove-Item -Path "Function:\$functionName" -ErrorAction Ignore
                        }
                    }
                }
            }
        }

        It "Should pass ExcludePassword to password-aware copy commands" {
            InModuleScope "dbatools" {
                $functionNames = @(
                    "Connect-DbaInstance",
                    "Copy-DbaCredential",
                    "Copy-DbaDbMail",
                    "Copy-DbaLinkedServer",
                    "Test-FunctionInterrupt",
                    "Write-ProgressHelper"
                )
                $originalFunctions = @{ }
                foreach ($functionName in $functionNames) {
                    if (Test-Path "Function:\$functionName") {
                        $originalFunctions[$functionName] = (Get-Item -Path "Function:\$functionName").ScriptBlock
                    }
                }

                try {
                    function Test-FunctionInterrupt { $false }
                    function Write-ProgressHelper { }
                    function Connect-DbaInstance {
                        param(
                            $SqlInstance,
                            $SqlCredential,
                            [switch]$DedicatedAdminConnection
                        )

                        if ($DedicatedAdminConnection) {
                            $script:dacConnections += $SqlInstance.ToString()
                        }

                        [PSCustomObject]@{
                            Name               = $SqlInstance.ToString()
                            DomainInstanceName = $SqlInstance.ToString()
                        }
                    }
                    function Copy-DbaCredential {
                        param(
                            $Source,
                            $Destination,
                            $Credential,
                            [switch]$ExcludePassword,
                            [switch]$Force
                        )

                        $script:copyCredentialCall = [PSCustomObject]@{
                            Credential      = $Credential
                            ExcludePassword = $ExcludePassword.IsPresent
                        }
                    }
                    function Copy-DbaDbMail {
                        param(
                            $Source,
                            $Destination,
                            $Credential,
                            [switch]$ExcludePassword,
                            [switch]$Force
                        )

                        $script:copyDbMailCall = [PSCustomObject]@{
                            Credential      = $Credential
                            ExcludePassword = $ExcludePassword.IsPresent
                        }
                    }
                    function Copy-DbaLinkedServer {
                        param(
                            $Source,
                            $Destination,
                            $Credential,
                            [switch]$ExcludePassword,
                            [switch]$Force
                        )

                        $script:copyLinkedServerCall = [PSCustomObject]@{
                            Credential      = $Credential
                            ExcludePassword = $ExcludePassword.IsPresent
                        }
                    }

                    $script:dacConnections = @()
                    $script:copyCredentialCall = $null
                    $script:copyDbMailCall = $null
                    $script:copyLinkedServerCall = $null

                    $exclude = @(
                        "AgentAlert",
                        "AgentCategory",
                        "AgentJob",
                        "AgentOperator",
                        "AgentProxy",
                        "AgentSchedule",
                        "CustomErrors",
                        "DatabaseOwner",
                        "LoginPermissions",
                        "Logins",
                        "SpConfigure",
                        "SystemTriggers"
                    )
                    $securePassword = ConvertTo-SecureString "Password1!" -AsPlainText -Force
                    $credential = New-Object System.Management.Automation.PSCredential("contoso\syncuser", $securePassword)

                    $null = Sync-DbaAvailabilityGroup -Primary "sql1" -Secondary "sql2" -Credential $credential -ExcludePassword -Exclude $exclude

                    $script:dacConnections | Should -BeNullOrEmpty
                    $script:copyCredentialCall.Credential.UserName | Should -Be "contoso\syncuser"
                    $script:copyCredentialCall.ExcludePassword | Should -BeTrue
                    $script:copyDbMailCall.Credential.UserName | Should -Be "contoso\syncuser"
                    $script:copyDbMailCall.ExcludePassword | Should -BeTrue
                    $script:copyLinkedServerCall.Credential.UserName | Should -Be "contoso\syncuser"
                    $script:copyLinkedServerCall.ExcludePassword | Should -BeTrue
                } finally {
                    foreach ($functionName in $functionNames) {
                        if ($originalFunctions.ContainsKey($functionName)) {
                            Set-Item -Path "Function:\$functionName" -Value $originalFunctions[$functionName]
                        } else {
                            Remove-Item -Path "Function:\$functionName" -ErrorAction Ignore
                        }
                    }
                }
            }
        }
    }

    Context "Agent job sync behavior" {
        It "Should request only local jobs and keep local jobs in category 1" {
            InModuleScope "dbatools" {
                $functionNames = @(
                    "Connect-DbaInstance",
                    "Copy-DbaAgentJob",
                    "Get-DbaAgentJob",
                    "Test-FunctionInterrupt",
                    "Write-ProgressHelper"
                )
                $originalFunctions = @{ }
                foreach ($functionName in $functionNames) {
                    if (Test-Path "Function:\$functionName") {
                        $originalFunctions[$functionName] = (Get-Item -Path "Function:\$functionName").ScriptBlock
                    }
                }

                try {
                    function Test-FunctionInterrupt { $false }
                    function Write-ProgressHelper { }
                    function Connect-DbaInstance {
                        param(
                            $SqlInstance,
                            $SqlCredential,
                            [switch]$DedicatedAdminConnection
                        )

                        [PSCustomObject]@{
                            Name               = $SqlInstance.ToString()
                            DomainInstanceName = $SqlInstance.ToString()
                        }
                    }
                    function Get-DbaAgentJob {
                        param(
                            $SqlInstance,
                            $Job,
                            $ExcludeJob,
                            $Type
                        )

                        $script:getAgentJobCall = [PSCustomObject]@{
                            SqlInstance = $SqlInstance
                            Type        = $Type
                        }

                        [PSCustomObject]@{
                            Name       = "dbatoolsci_localjob"
                            JobType    = "Local"
                            CategoryID = 1
                        }
                    }
                    function Copy-DbaAgentJob {
                        param(
                            $Destination,
                            [switch]$Force,
                            [switch]$DisableOnDestination,
                            $InputObject
                        )

                        $script:copyAgentJobCall = [PSCustomObject]@{
                            Destination = $Destination
                            InputObject = $InputObject
                        }
                    }

                    $script:getAgentJobCall = $null
                    $script:copyAgentJobCall = $null

                    $exclude = @(
                        "AgentAlert",
                        "AgentCategory",
                        "AgentOperator",
                        "AgentProxy",
                        "AgentSchedule",
                        "Credentials",
                        "CustomErrors",
                        "DatabaseMail",
                        "DatabaseOwner",
                        "LinkedServers",
                        "LoginPermissions",
                        "Logins",
                        "SpConfigure",
                        "SystemTriggers"
                    )

                    $null = Sync-DbaAvailabilityGroup -Primary "sql1" -Secondary "sql2" -Exclude $exclude

                    $script:getAgentJobCall.SqlInstance.Name | Should -Be "sql1"
                    $script:getAgentJobCall.Type | Should -Be "Local"
                    $script:copyAgentJobCall.InputObject.Name | Should -Be "dbatoolsci_localjob"
                    $script:copyAgentJobCall.InputObject.JobType | Should -Be "Local"
                } finally {
                    foreach ($functionName in $functionNames) {
                        if ($originalFunctions.ContainsKey($functionName)) {
                            Set-Item -Path "Function:\$functionName" -Value $originalFunctions[$functionName]
                        } else {
                            Remove-Item -Path "Function:\$functionName" -ErrorAction Ignore
                        }
                    }
                }
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $syncLogin = "dbatoolsci_syncag_$random"
        $dupeLogin = "dbatoolsci_syncdupe_$random"

        # The sync is only meaningful against an availability group that actually has a secondary
        # replica, so the group is discovered rather than created: a single-replica group would
        # leave the sync with nothing to copy to and the leg would prove nothing. Where no reachable
        # instance hosts one, the AG legs report a skip reason instead of failing setup for the
        # guard legs too, which need no HADR at all.
        $agReady = $false
        $agSkipReason = "no reachable instance hosts a >=2-replica availability group"
        $agObject = $null
        $agSecondaryNames = @()
        $primaryInstance = $TestConfig.InstanceSingle

        # Each candidate is tried inside its own try, because one unreachable instance must not
        # end the search for the others. The secondaries are connected too: the sync copies TO
        # them, so a group whose replicas are listed but not reachable would fail the live legs
        # rather than skip them, which is the failure this discovery exists to avoid.
        $candidates = @($TestConfig.InstanceSingle, $TestConfig.InstanceHadr, $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2) | Where-Object { $PSItem } | Select-Object -Unique
        foreach ($candidate in $candidates) {
            try {
                $candidateServer = Connect-DbaInstance -SqlInstance $candidate
                if (-not $candidateServer.IsHadrEnabled) {
                    continue
                }

                $candidateAg = Get-DbaAvailabilityGroup -SqlInstance $candidateServer | Where-Object { $PSItem.AvailabilityReplicas.Count -ge 2 } | Select-Object -First 1
                if (-not $candidateAg) {
                    continue
                }

                $candidateSecondaries = @(($candidateAg.AvailabilityReplicas | Where-Object Name -ne $candidateServer.DomainInstanceName).Name | Select-Object -Unique)
                foreach ($candidateSecondary in $candidateSecondaries) {
                    $null = Connect-DbaInstance -SqlInstance $candidateSecondary
                }

                $primaryInstance = $candidate
                $agObject = $candidateAg
                $agSecondaryNames = $candidateSecondaries
                $agReady = $true
                break
            } catch {
                $agSkipReason = "availability-group discovery failed on $($candidate): $($PSItem.Exception.Message)"
            }
        }

        # Every object type the command knows about except Logins. The live legs below copy exactly
        # one named login and nothing else, so a shared lab instance cannot be reconfigured by them.
        $excludeAllButLogins = @(
            "AgentAlert",
            "AgentCategory",
            "AgentJob",
            "AgentOperator",
            "AgentProxy",
            "AgentSchedule",
            "Credentials",
            "CustomErrors",
            "DatabaseMail",
            "DatabaseOwner",
            "LinkedServers",
            "LoginPermissions",
            "SpConfigure",
            "SystemTriggers"
        )

        # Generated per run rather than a shared literal, so a cleanup that fails cannot leave a
        # login behind whose password is written down in the repo.
        $loginPassword = ConvertTo-SecureString -String "$([System.Guid]::NewGuid())aA1!" -AsPlainText -Force
        if ($agReady) {
            foreach ($fixtureLogin in @($syncLogin, $dupeLogin)) {
                $splatNewLogin = @{
                    SqlInstance    = $primaryInstance
                    Login          = $fixtureLogin
                    SecurePassword = $loginPassword
                }
                $null = New-DbaLogin @splatNewLogin
            }
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($agReady) {
            $splatRemoveLogins = @{
                SqlInstance = @($primaryInstance) + $agSecondaryNames
                Login       = @($syncLogin, $dupeLogin)
                ErrorAction = "SilentlyContinue"
            }
            $null = Get-DbaLogin @splatRemoveLogins | Remove-DbaLogin -ErrorAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Guarding before the sync" {
        It "Warns once and returns nothing when neither Primary nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Sync-DbaAvailabilityGroup @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must supply either -Primary or an Input Object"
        }

        It "Warns once and returns nothing when Primary is supplied without a Secondary or AvailabilityGroup" {
            $splatNoTarget = @{
                Primary         = $primaryInstance
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Sync-DbaAvailabilityGroup @splatNoTarget)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must specify a secondary or an availability group."
        }
    }

    Context "Syncing a login to the secondary replicas" {
        It "Does not create the login on any secondary under -WhatIf" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            $splatWhatIfSync = @{
                Primary           = $primaryInstance
                AvailabilityGroup = $agObject.Name
                Login             = $syncLogin
                Exclude           = $excludeAllButLogins
                WhatIf            = $true
            }
            $null = Sync-DbaAvailabilityGroup @splatWhatIfSync

            Get-DbaLogin -SqlInstance $agSecondaryNames -Login $syncLogin | Should -BeNullOrEmpty
        }

        It "Creates the login on every secondary when -WhatIf is not supplied" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            $splatRealSync = @{
                Primary           = $primaryInstance
                AvailabilityGroup = $agObject.Name
                Login             = $syncLogin
                Exclude           = $excludeAllButLogins
            }
            $syncResult = @(Sync-DbaAvailabilityGroup @splatRealSync)

            $syncResult.Count | Should -Be $agSecondaryNames.Count
            @($syncResult.Status | Sort-Object -Unique) | Should -Be @("Successful")
            @(Get-DbaLogin -SqlInstance $agSecondaryNames -Login $syncLogin).Count | Should -Be $agSecondaryNames.Count
        }
    }

    Context "When the same availability group is piped in twice" {
        It "Syncs one combination rather than one per record" {
            if (-not $agReady) {
                Set-ItResult -Skipped -Because $agSkipReason
                return
            }
            $splatPipedSync = @{
                Login   = $dupeLogin
                Exclude = $excludeAllButLogins
            }
            # The dedupe is the only thing standing between two records and two syncs, and it reads
            # a list the first record has to have left behind. A second combination would copy the
            # login it just created and come back Skipped, so count and status both have to hold.
            $dupeResult = @(@($agObject, $agObject) | Sync-DbaAvailabilityGroup @splatPipedSync)

            $dupeResult.Count | Should -Be $agSecondaryNames.Count
            @($dupeResult.Status | Sort-Object -Unique) | Should -Be @("Successful")
        }
    }

    Context "When the secondary cannot be reached" {
        BeforeAll {
            $originalConnectTimeout = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            $null = Set-DbatoolsConfig -FullName sql.connection.timeout -Value 1
        }

        AfterAll {
            $null = Set-DbatoolsConfig -FullName sql.connection.timeout -Value $originalConnectTimeout
        }

        It "Warns that no secondaries were found" {
            $splatUnreachable = @{
                Primary         = $primaryInstance
                Secondary       = $TestConfig.InstanceUnreachable
                Exclude         = $excludeAllButLogins
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $null = Sync-DbaAvailabilityGroup @splatUnreachable

            $payloads = @($warn | ForEach-Object { $PSItem.Message -replace "^(\[[^\]]*\]\s*)+", "" })
            $payloads | Should -Contain "No secondaries found."
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

`$resolved = Get-Command -Name Sync-DbaAvailabilityGroup -ErrorAction SilentlyContinue

`$splatResolveAll = @{

    Name        = "Sync-DbaAvailabilityGroup"

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
