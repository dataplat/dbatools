#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDbMail",
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
                "Credential",
                "Type",
                "Force",
                "ExcludePassword",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should keep -Type in its own parameter set" {
            # The only parameter the source scopes to a set, and the only thing that makes the
            # command carry two sets at all.
            $typeParameter = (Get-Command $CommandName).Parameters["Type"]
            @($typeParameter.ParameterSets.Keys) | Should -Be "SpecificTypes"
            @($typeParameter.Attributes.ValidValues | Sort-Object) | Should -Be @("Accounts", "ConfigurationValues", "MailServers", "Profiles")
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $sourceInstance = $TestConfig.InstanceCopy1
        $destInstance = $TestConfig.InstanceCopy2

        # A GUID rather than Get-Random: the cleanup deletes these names unconditionally on both
        # instances, so a collision with a concurrent run would destroy that run's mail objects.
        $mailStem = "dbatoolsci_dbmail_$([guid]::NewGuid().ToString("N"))"
        $accountName = "${mailStem}_account"
        $profileName = "${mailStem}_profile"
        $mailServerName = "smtp.dbatools.io"
        $smtpUserName = "${mailStem}_smtp"
        # Fixture only. It reaches no real SMTP server - the point of it is that Database Mail
        # stores it as a credential, which is the branch the mail server copy has to carry.
        $smtpPassword = "dbatoolsci_smtp_pw"

        $mailObjectsCreated = @()

        # Database Mail XPs is instance-wide, and the two instances do not have to start from the
        # same value. Captured per instance rather than assumed, because restoring a guessed value
        # would leave an instance in a state its other users did not have.
        $originalMailXps = @{}
        foreach ($instance in @($sourceInstance, $destInstance | Select-Object -Unique)) {
            $originalMailXps[$instance] = (Get-DbaSpConfigure -SqlInstance $instance -Name "Database Mail XPs").ConfiguredValue
            # Set-DbaSpConfigure throws rather than no-ops when the value already matches.
            if ($originalMailXps[$instance] -ne 1) {
                $splatEnableMailXps = @{
                    SqlInstance = $instance
                    Name        = "Database Mail XPs"
                    Value       = 1
                }
                $null = Set-DbaSpConfigure @splatEnableMailXps
            }
        }

        # The command copies the source's global Database Mail configuration values onto the
        # destination on every unfiltered call. Those are instance-wide settings belonging to
        # whoever set them, so record them and put back anything this run changed.
        $mailConfigurationQuery = "SELECT paramname, paramvalue FROM msdb.dbo.sysmail_configuration"
        $originalDestMailConfiguration = @(Invoke-DbaQuery -SqlInstance $destInstance -Query $mailConfigurationQuery)

        function Get-MailObjectInventory {
            param($SqlInstance)
            $splatInventory = @{
                SqlInstance = $SqlInstance
                Query       = "SELECT 'Account' AS ObjectType, name AS ObjectName FROM msdb.dbo.sysmail_account UNION ALL SELECT 'Profile', name FROM msdb.dbo.sysmail_profile"
            }
            Invoke-DbaQuery @splatInventory
        }

        # Every unfiltered leg hands the command the source's whole mail configuration, so anything
        # already there would be copied onto the destination. Establish the source is empty before
        # the fixture exists and those legs provably cannot carry a stranger's account or profile
        # across. This throws rather than skipping: a leg that quietly stops covering the
        # unfiltered path is worth less than a red one, and the message names what is in the way.
        $preexistingSourceMail = @(Get-MailObjectInventory -SqlInstance $sourceInstance)
        if ($preexistingSourceMail.Count -gt 0) {
            $preexistingList = ($preexistingSourceMail | ForEach-Object { "$($PSItem.ObjectType) $($PSItem.ObjectName)" }) -join ", "
            throw "$sourceInstance already carries Database Mail objects ($preexistingList) - the unfiltered legs would copy them to $destInstance, so this suite will not run against it."
        }

        # The destination is allowed to carry foreign mail objects: nothing here deletes one, and
        # the source is empty above, so no -Force leg can reach a name this run did not create.
        # It must not already carry THESE names though, or the suite would adopt mail objects it
        # did not create and the cleanup would then delete them.
        $preexistingDestMail = @(Get-MailObjectInventory -SqlInstance $destInstance) |
            Where-Object { $PSItem.ObjectName -in $accountName, $profileName }
        if (@($preexistingDestMail).Count -gt 0) {
            throw "$destInstance already carries $accountName or $profileName - this suite will not adopt mail objects it did not create, because the cleanup would then delete them."
        }

        # Raw sysmail procedures rather than New-DbaDbMailAccount: only @username/@password create
        # the SMTP credential that puts a credential_id on the mail server row, and that is the
        # branch the mail server copy has to script across.
        #
        # Recorded before created, not after. A create that fails partway leaks the object if
        # nothing has recorded it yet, and the cleanup deletes through an IF EXISTS, so a name that
        # was never created finds nothing.
        $splatCreateAccount = @{
            SqlInstance = $sourceInstance
            Query       = "EXEC msdb.dbo.sysmail_add_account_sp @account_name = N'$accountName', @email_address = N'dbatoolssci@dbatools.io', @display_name = N'dbatoolsci mail alerts', @replyto_address = N'no-reply@dbatools.io', @description = N'Mail account for email alerts', @mailserver_name = N'$mailServerName', @mailserver_type = N'SMTP', @port = 25, @username = N'$smtpUserName', @password = N'$smtpPassword', @use_default_credentials = 0"
        }
        $mailObjectsCreated += [PSCustomObject]@{ SqlInstance = $sourceInstance; ObjectType = "Account"; ObjectName = $accountName }
        Invoke-DbaQuery @splatCreateAccount

        $splatCreateProfile = @{
            SqlInstance = $sourceInstance
            Query       = "EXEC msdb.dbo.sysmail_add_profile_sp @profile_name = N'$profileName', @description = N'Mail profile for email alerts'"
        }
        $mailObjectsCreated += [PSCustomObject]@{ SqlInstance = $sourceInstance; ObjectType = "Profile"; ObjectName = $profileName }
        Invoke-DbaQuery @splatCreateProfile

        $splatLinkProfile = @{
            SqlInstance = $sourceInstance
            Query       = "EXEC msdb.dbo.sysmail_add_profileaccount_sp @profile_name = N'$profileName', @account_name = N'$accountName', @sequence_number = 1"
        }
        Invoke-DbaQuery @splatLinkProfile

        # The destination copies carry the same names, so they go on the cleanup list here rather
        # than in whichever leg happened to create them first.
        $mailObjectsCreated += [PSCustomObject]@{ SqlInstance = $destInstance; ObjectType = "Profile"; ObjectName = $profileName }
        $mailObjectsCreated += [PSCustomObject]@{ SqlInstance = $destInstance; ObjectType = "Account"; ObjectName = $accountName }

        # Read-backs the legs below share. None of them is ever modified.
        $splatDestAccountRow = @{
            SqlInstance = $destInstance
            Query       = "SELECT account_id, name FROM msdb.dbo.sysmail_account WHERE name = N'$accountName'"
        }
        $splatDestProfileRow = @{
            SqlInstance = $destInstance
            Query       = "SELECT profile_id, name FROM msdb.dbo.sysmail_profile WHERE name = N'$profileName'"
        }
        $splatDestMailServerRow = @{
            SqlInstance = $destInstance
            Query       = "SELECT s.servername, s.port, s.credential_id FROM msdb.dbo.sysmail_server AS s JOIN msdb.dbo.sysmail_account AS a ON a.account_id = s.account_id WHERE a.name = N'$accountName'"
        }
        $splatDestMailXps = @{
            SqlInstance = $destInstance
            Name        = "Database Mail XPs"
        }
        $splatCopyMail = @{
            Source        = $sourceInstance
            Destination   = $destInstance
            WarningAction = "SilentlyContinue"
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Each restoration stands on its own. These are instance-wide settings and shared mail
        # configuration on a lab other windows are using, so one failure must not skip the rest.
        # The collected failures are re-raised at the end so a broken cleanup still fails the run.
        $cleanupFailures = @()

        # Profiles first: the profile-account link keeps an account from being deleted while a
        # profile still references it.
        foreach ($mailObject in ($mailObjectsCreated | Where-Object ObjectType -eq "Profile")) {
            try {
                $splatDeleteProfile = @{
                    SqlInstance = $mailObject.SqlInstance
                    Query       = "IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile WHERE name = N'$($mailObject.ObjectName)') EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = N'$($mailObject.ObjectName)'"
                }
                Invoke-DbaQuery @splatDeleteProfile
            } catch {
                $cleanupFailures += "profile $($mailObject.ObjectName) on $($mailObject.SqlInstance): $($PSItem.Exception.Message)"
            }
        }

        foreach ($mailObject in ($mailObjectsCreated | Where-Object ObjectType -eq "Account")) {
            try {
                $splatDeleteAccount = @{
                    SqlInstance = $mailObject.SqlInstance
                    Query       = "IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_account WHERE name = N'$($mailObject.ObjectName)') EXEC msdb.dbo.sysmail_delete_account_sp @account_name = N'$($mailObject.ObjectName)'"
                }
                Invoke-DbaQuery @splatDeleteAccount
            } catch {
                $cleanupFailures += "account $($mailObject.ObjectName) on $($mailObject.SqlInstance): $($PSItem.Exception.Message)"
            }
        }

        # Driven by what was captured, and only where the value actually moved: sysmail_configure_sp
        # on a value nobody changed would rewrite a setting this run has no business touching.
        try {
            $currentDestMailConfiguration = @(Invoke-DbaQuery -SqlInstance $destInstance -Query $mailConfigurationQuery)
            foreach ($originalSetting in $originalDestMailConfiguration) {
                $currentSetting = @($currentDestMailConfiguration | Where-Object paramname -eq $originalSetting.paramname)
                if ($currentSetting.Count -eq 0 -or $currentSetting[0].paramvalue -eq $originalSetting.paramvalue) { continue }
                $splatRestoreSetting = @{
                    SqlInstance = $destInstance
                    Query       = "EXEC msdb.dbo.sysmail_configure_sp @parameter_name = N'$($originalSetting.paramname)', @parameter_value = N'$($originalSetting.paramvalue)'"
                }
                Invoke-DbaQuery @splatRestoreSetting
            }
        } catch {
            $cleanupFailures += "mail configuration on ${destInstance}: $($PSItem.Exception.Message)"
        }

        # Driven by the captured hashtable, not by the two instance names: a setup that threw before
        # the second snapshot leaves no entry for it, and a missing entry would hand
        # Set-DbaSpConfigure a $null Value that binds as 0.
        foreach ($restoreInstance in @($originalMailXps.Keys)) {
            try {
                if ((Get-DbaSpConfigure -SqlInstance $restoreInstance -Name "Database Mail XPs").ConfiguredValue -ne $originalMailXps[$restoreInstance]) {
                    $splatRestoreMailXps = @{
                        SqlInstance = $restoreInstance
                        Name        = "Database Mail XPs"
                        Value       = $originalMailXps[$restoreInstance]
                    }
                    $null = Set-DbaSpConfigure @splatRestoreMailXps
                }
            } catch {
                $cleanupFailures += "Database Mail XPs on ${restoreInstance}: $($PSItem.Exception.Message)"
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

        if ($cleanupFailures.Count -gt 0) {
            throw "AfterAll could not restore: $($cleanupFailures -join " | ")"
        }
    }

    Context "When copying Database Mail" {
        BeforeEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Only this run's names. The destination is allowed to carry foreign mail objects and
            # none of them is this suite's to remove.
            $splatResetDestination = @{
                SqlInstance = $destInstance
                Query       = "IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile WHERE name = N'$profileName') EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = N'$profileName'; IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_account WHERE name = N'$accountName') EXEC msdb.dbo.sysmail_delete_account_sp @account_name = N'$accountName'"
            }
            Invoke-DbaQuery @splatResetDestination

            if ((Get-DbaSpConfigure @splatDestMailXps).ConfiguredValue -ne 1) {
                $splatRestoreLegMailXps = @{
                    SqlInstance = $destInstance
                    Name        = "Database Mail XPs"
                    Value       = 1
                }
                $null = Set-DbaSpConfigure @splatRestoreLegMailXps
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should copy every mail component and land each one on the destination" {
            # No -Type on purpose: this is the whole-configuration path, and it is the only one
            # that reaches the Database Mail XPs block after the four copies.
            $copyResults = @(Copy-DbaDbMail @splatCopyMail)

            # The emission order IS the workflow - configuration, accounts, profiles, mail servers,
            # then the XPs verdict. A port that reordered the four helpers would still report four
            # successes.
            @($copyResults | ForEach-Object Type) | Should -Be @("Mail Configuration", "Mail Account", "Mail Profile", "Mail Server", "Mail Configuration")
            @($copyResults | ForEach-Object Name) | Should -Be @("Server Configuration", $accountName, $profileName, $mailServerName, "Database Mail XPs")
            @($copyResults | Select-Object -First 4 | ForEach-Object Status) | Should -Be @("Successful", "Successful", "Successful", "Successful")

            # Status text is what the command says about itself; these are what the destination says.
            @(Invoke-DbaQuery @splatDestAccountRow).Count | Should -Be 1
            @(Invoke-DbaQuery @splatDestProfileRow).Count | Should -Be 1

            $landedMailServer = @(Invoke-DbaQuery @splatDestMailServerRow)
            $landedMailServer.Count | Should -Be 1
            $landedMailServer[0].servername | Should -Be $mailServerName
            $landedMailServer[0].port | Should -Be 25
            # The SMTP credential is the reason the mail server copy opens a dedicated admin
            # connection at all - a mail server scripted without it lands with no credential.
            $landedMailServer[0].credential_id | Should -Not -BeNullOrEmpty

            # A profile is worth nothing to Database Mail without its account link, and the link is
            # scripted separately from the profile itself.
            $splatProfileAccountLink = @{
                SqlInstance = $destInstance
                Query       = "SELECT pa.sequence_number FROM msdb.dbo.sysmail_profileaccount AS pa JOIN msdb.dbo.sysmail_profile AS p ON p.profile_id = pa.profile_id JOIN msdb.dbo.sysmail_account AS a ON a.account_id = pa.account_id WHERE p.name = N'$profileName' AND a.name = N'$accountName'"
            }
            @(Invoke-DbaQuery @splatProfileAccountLink).Count | Should -Be 1
        }

        It "Should not create anything on the destination with -WhatIf" {
            $whatIfResults = @(Copy-DbaDbMail @splatCopyMail -WhatIf)

            # Not empty, and that is the point. Four of the five status objects sit behind a
            # ShouldProcess gate and vanish; the Database Mail XPs verdict does not - the
            # already-enabled arm emits with no gate in front of it, so a dry run still reports it.
            # An emitted-nothing assertion here would be asserting a bug.
            $whatIfResults.Count | Should -Be 1
            $whatIfResults[0].Name | Should -Be "Database Mail XPs"
            $whatIfResults[0].Status | Should -Be "Skipped"

            # Three absence assertions, not one. Every gate in this command sits in front of a
            # different write, and an output check alone cannot tell a gated write from an ungated
            # one whose status object was suppressed.
            @(Invoke-DbaQuery @splatDestAccountRow).Count | Should -Be 0
            @(Invoke-DbaQuery @splatDestProfileRow).Count | Should -Be 0
            @(Invoke-DbaQuery @splatDestMailServerRow).Count | Should -Be 0
        }

        It "Should skip mail objects that already exist on the destination" {
            $null = Copy-DbaDbMail @splatCopyMail

            $skipResults = @(Copy-DbaDbMail @splatCopyMail)
            foreach ($skippedType in "Mail Account", "Mail Profile", "Mail Server") {
                $skipObject = $skipResults | Where-Object Type -eq $skippedType
                $skipObject.Status | Should -Be "Skipped" -Because "$skippedType already exists on the destination"
                $skipObject.Notes | Should -Be "Already exists on destination"
            }

            # The third arm of the Database Mail XPs block, and the only one the enable leg below
            # cannot reach.
            $xpsObject = $skipResults | Where-Object Name -eq "Database Mail XPs"
            $xpsObject.Status | Should -Be "Skipped"
            $xpsObject.Notes | Should -Be "Database Mail XPs already enabled on destination"
        }

        It "Should drop and recreate existing mail objects with -Force" {
            $null = Copy-DbaDbMail @splatCopyMail
            $originalAccountId = (Invoke-DbaQuery @splatDestAccountRow).account_id
            $originalProfileId = (Invoke-DbaQuery @splatDestProfileRow).profile_id

            $forceResults = @(Copy-DbaDbMail @splatCopyMail -Force)
            ($forceResults | Where-Object Type -eq "Mail Account").Status | Should -Be "Successful"
            ($forceResults | Where-Object Type -eq "Mail Profile").Status | Should -Be "Successful"

            # Status alone cannot tell a real drop-and-recreate from a no-op that reports success.
            (Invoke-DbaQuery @splatDestAccountRow).account_id | Should -Not -Be $originalAccountId
            (Invoke-DbaQuery @splatDestProfileRow).profile_id | Should -Not -Be $originalProfileId
        }

        It "Should enable Database Mail XPs on the destination when the source has it on" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaSpConfigure -SqlInstance $destInstance -Name "Database Mail XPs" -Value 0
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $enableResults = @(Copy-DbaDbMail @splatCopyMail)

            $xpsObject = $enableResults | Where-Object Name -eq "Database Mail XPs"
            $xpsObject.Status | Should -Be "Successful"
            $xpsObject.Notes | Should -Be "Database Mail XPs enabled on destination"
            # Read back from the instance: the status object is the command's own account of itself.
            (Get-DbaSpConfigure @splatDestMailXps).ConfiguredValue | Should -Be 1
        }

        It "Should copy only the named component with -Type" {
            $splatTypeAccounts = @{
                Source        = $sourceInstance
                Destination   = $destInstance
                Type          = "Accounts"
                WarningAction = "SilentlyContinue"
            }
            $typeResults = @(Copy-DbaDbMail @splatTypeAccounts)

            @($typeResults | ForEach-Object Type) | Should -Be @("Mail Account")
            $typeResults[0].Status | Should -Be "Successful"
            @(Invoke-DbaQuery @splatDestAccountRow).Count | Should -Be 1
            @(Invoke-DbaQuery @splatDestProfileRow).Count | Should -Be 0
            # The typed path returns before the Database Mail XPs block, so no XPs verdict is
            # emitted at all - which is what distinguishes it from a filter applied to the output.
            @($typeResults | Where-Object Name -eq "Database Mail XPs").Count | Should -Be 0
        }

        It "Should run one pass per component when -Type names several" {
            $splatTypePair = @{
                Source        = $sourceInstance
                Destination   = $destInstance
                Type          = "Accounts", "Profiles"
                WarningAction = "SilentlyContinue"
            }
            $pairResults = @(Copy-DbaDbMail @splatTypePair)

            # -Type drives a switch over the array, so each named component gets its own pass - and
            # the mail servers that a whole-configuration call would have copied stay untouched.
            @($pairResults | ForEach-Object Type | Sort-Object) | Should -Be @("Mail Account", "Mail Profile")
            @(Invoke-DbaQuery @splatDestAccountRow).Count | Should -Be 1
            @(Invoke-DbaQuery @splatDestProfileRow).Count | Should -Be 1
        }

        It "Should copy over a normal connection with -ExcludePassword" {
            # The one leg that does not open a dedicated admin connection: -ExcludePassword takes
            # the ordinary Connect-DbaInstance branch and skips credential decryption entirely. A
            # port that collapsed the two connection branches copies fine here and reds nowhere
            # else, because every other leg goes down the DAC side.
            $splatExcludePassword = @{
                Source          = $sourceInstance
                Destination     = $destInstance
                ExcludePassword = $true
                WarningAction   = "SilentlyContinue"
            }
            $excludeResults = @(Copy-DbaDbMail @splatExcludePassword)

            ($excludeResults | Where-Object Type -eq "Mail Server").Status | Should -Be "Successful"
            @(Invoke-DbaQuery @splatDestMailServerRow).Count | Should -Be 1
        }

        It "Should process every destination from one source read" {
            # The cross-record leg. The source connection, its Mail collections and the source
            # regex are all built once, before the destination loop, so a port that consumed them
            # while walking the first destination would hand the second nothing - and every
            # per-destination assertion above would still pass on the first pass alone. The same
            # destination twice makes the second pass assert something the first cannot produce.
            $splatTwoDestinations = @{
                Source        = $sourceInstance
                Destination   = $destInstance, $destInstance
                WarningAction = "SilentlyContinue"
            }
            $crossResults = @(Copy-DbaDbMail @splatTwoDestinations)

            $crossAccounts = @($crossResults | Where-Object Type -eq "Mail Account")
            $crossAccounts.Count | Should -Be 2
            $crossAccounts[0].Status | Should -Be "Successful"
            $crossAccounts[1].Status | Should -Be "Skipped"
            $crossAccounts[1].Notes | Should -Be "Already exists on destination"

            $crossProfiles = @($crossResults | Where-Object Type -eq "Mail Profile")
            $crossProfiles.Count | Should -Be 2
            $crossProfiles[0].Status | Should -Be "Successful"
            $crossProfiles[1].Status | Should -Be "Skipped"
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
`$resolved = Get-Command -Name Copy-DbaDbMail -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaDbMail"
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
