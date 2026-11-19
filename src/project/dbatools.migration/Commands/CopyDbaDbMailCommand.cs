#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies the Database Mail configuration - configuration values, accounts, profiles and mail
/// servers - from a source SQL Server instance to one or more destinations. Port of
/// public/Copy-DbaDbMail.ps1. The whole workflow rides one module-scoped PowerShell hop because it
/// leans on a dedicated admin connection, the private service-master-key decryption helper, SMO
/// Mail collection enumeration and Script(), and Select-DefaultView decoration, all of which keep
/// the retired function's engine semantics there. The compiled cmdlet supplies the real
/// ShouldProcess runtime. Surface pinned by migration/baselines/Copy-DbaDbMail.json.
/// </summary>
[Cmdlet(VerbsCommon.Copy, "DbaDbMail", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaDbMailCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance holding the Database Mail configuration to copy.</summary>
    [Parameter(Mandatory = true)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instances.</summary>
    [Parameter(Mandatory = true)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Windows credential used to reach the source OS when mail server passwords are decrypted.</summary>
    [Parameter]
    public PSCredential? Credential { get; set; }

    /// <summary>Limit the migration to these Database Mail component types.</summary>
    [Parameter(ParameterSetName = "SpecificTypes")]
    [ValidateSet("ConfigurationValues", "Profiles", "Accounts", "MailServers")]
    public string[]? Type { get; set; }

    /// <summary>Copy mail server definitions without carrying over the SMTP passwords.</summary>
    [Parameter]
    public SwitchParameter ExcludePassword { get; set; }

    /// <summary>Drop and recreate mail objects that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, BodyScript,
            Source, SourceSqlCredential, Destination, DestinationSqlCredential, Credential,
            Type, ExcludePassword.ToBool(), Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: begin, process and end collapse into one ProcessRecord because no parameter takes
    // pipeline input. The nested helpers keep their names so Write-Message still attributes to
    // them, but every $pscmdlet.ShouldProcess becomes $__realCmdlet.ShouldProcess - a nested
    // advanced function inside the hop would resolve $WhatIfPreference through the module scope
    // chain and never see the caller's bound -WhatIf.
    //
    // The end block's disconnect moves into a finally, matching Copy-DbaCredential in this
    // satellite: the source leaks the dedicated admin connection when the body throws, and only
    // one DAC per instance exists, so the leak blocks every later run on a shared box.
    private const string BodyScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $Credential, $Type, $ExcludePassword, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, $SourceSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, $DestinationSqlCredential, $Credential, [string[]]$Type, $ExcludePassword, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)

    if ($Force) { $ConfirmPreference = 'none' }

    function Copy-DbaDbMailConfig {
        Write-Message -Message "Migrating mail server configuration values." -Level Verbose
        $copyMailConfigStatus = [PSCustomObject]@{
            SourceServer      = $sourceServerName
            DestinationServer = $destServer.Name
            Name              = "Server Configuration"
            Type              = "Mail Configuration"
            Status            = $null
            Notes             = $null
            DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
        }
        if ($__realCmdlet.ShouldProcess($destinstance, "Migrating all mail server configuration values.")) {
            try {
                $sql = $mail.ConfigurationValues.Script() | Out-String
                $sql = $sql -replace [Regex]::Escape("'$Source'"), "'$destinstance'"
                Write-Message -Message $sql -Level Debug
                $destServer.Query($sql) | Out-Null
                $mail.ConfigurationValues.Refresh()
                $copyMailConfigStatus.Status = "Successful"
                $copyMailConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            } catch {
                $copyMailConfigStatus.Status = "Failed"
                $copyMailConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                Write-Message -Level Verbose -Message "Unable to update mail server configuration on $destinstance | $PSItem"
                continue
            }
        }
    }

    function Copy-DbaDatabaseAccount {
        $sourceAccounts = $sourceServer.Mail.Accounts
        $destAccounts = $destServer.Mail.Accounts

        Write-Message -Message "Migrating accounts." -Level Verbose
        foreach ($account in $sourceAccounts) {
            $accountName = [string]$account.name
            $newAccountName = $accountName -replace [Regex]::Escape($Source), $destinstance
            Write-Message -Message "Updating account name from '$accountName' to '$newAccountName'." -Level Verbose
            $copyMailAccountStatus = [PSCustomObject]@{
                SourceServer      = $sourceServerName
                DestinationServer = $destServer.Name
                Name              = $accountName
                Type              = "Mail Account"
                Status            = $null
                Notes             = $null
                DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
            }

            if ($accounts.count -gt 0 -and $accounts -notcontains $newAccountName) {
                continue
            }

            if ($destAccounts.name -contains $newAccountName) {
                if ($force -eq $false) {
                    If ($__realCmdlet.ShouldProcess($destinstance, "Account '$newAccountName' exists at destination. Use -Force to drop and migrate.")) {
                        $copyMailAccountStatus.Status = "Skipped"
                        $copyMailAccountStatus.Notes = "Already exists on destination"
                        $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Message "Account $newAccountName exists at destination. Use -Force to drop and migrate." -Level Verbose
                    }
                    continue
                }

                If ($__realCmdlet.ShouldProcess($destinstance, "Dropping account '$newAccountName' and recreating.")) {
                    try {
                        Write-Message -Message "Dropping account '$newAccountName'." -Level Verbose
                        $destServer.Mail.Accounts[$newAccountName].Drop()
                        $destServer.Mail.Accounts.Refresh()
                    } catch {
                        $copyMailAccountStatus.Status = "Failed"
                        $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue dropping and recreating mail account $newAccountName on $destinstance | $PSItem"
                        continue
                    }
                }
            }

            if ($__realCmdlet.ShouldProcess($destinstance, "Migrating account '$accountName'.")) {
                try {
                    Write-Message -Message "Copying mail account '$accountName'." -Level Verbose
                    $sql = $account.Script() | Out-String
                    $sql = $sql -replace "(?<=@account_name=N'[\d\w\s']*)$sourceRegEx(?=[\d\w\s']*',)", $destinstance
                    Write-Message -Message $sql -Level Debug
                    $destServer.Query($sql) | Out-Null
                    $copyMailAccountStatus.Status = "Successful"
                } catch {
                    $copyMailAccountStatus.Status = "Failed"
                    $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Issue copying mail account $accountName to $destinstance | $PSItem"
                    continue
                }
                $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
        }
    }

    function Copy-DbaDbMailProfile {

        $sourceProfiles = $sourceServer.Mail.Profiles
        $destProfiles = $destServer.Mail.Profiles

        Write-Message -Message "Migrating mail profiles." -Level Verbose
        foreach ($profile in $sourceProfiles) {

            $profileName = [string]$profile.name
            $newProfileName = $profileName -replace [Regex]::Escape($Source), $destinstance
            Write-Message -Message "Updating profile name from '$profileName' to '$newProfileName'." -Level Verbose
            $copyMailProfileStatus = [PSCustomObject]@{
                SourceServer      = $sourceServerName
                DestinationServer = $destServer.Name
                Name              = $profileName
                Type              = "Mail Profile"
                Status            = $null
                Notes             = $null
                DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
            }

            if ($profiles.count -gt 0 -and $profiles -notcontains $newProfileName) {
                continue
            }

            if ($destProfiles.name -contains $newProfileName) {
                if ($force -eq $false) {
                    If ($__realCmdlet.ShouldProcess($destinstance, "Profile '$newProfileName' exists at destination. Use -Force to drop and migrate.")) {
                        $copyMailProfileStatus.Status = "Skipped"
                        $copyMailProfileStatus.Notes = "Already exists on destination"
                        $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Message "Profile '$newProfileName' exists at destination. Use -Force to drop and migrate." -Level Verbose
                    }
                    continue
                }

                If ($__realCmdlet.ShouldProcess($destinstance, "Dropping profile '$newProfileName' and recreating.")) {
                    try {
                        Write-Message -Message "Dropping profile '$newProfileName'." -Level Verbose
                        $destServer.Mail.Profiles[$newProfileName].Drop()
                        $destServer.Mail.Profiles.Refresh()
                    } catch {
                        $copyMailProfileStatus.Status = "Failed"
                        $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue dropping mail profile $newProfileName on $destinstance | $PSItem"
                        continue
                    }
                }
            }

            if ($__realCmdlet.ShouldProcess($destinstance, "Migrating mail profile '$profileName'.")) {
                try {
                    Write-Message -Message "Copying mail profile '$profileName'." -Level Verbose
                    $sql = $profile.Script() | Out-String
                    $sql = $sql -replace "(?<=@account_name=N'[\d\w\s']*)$sourceRegEx(?=[\d\w\s']*',)", $destinstance
                    $sql = $sql -replace "(?<=@profile_name=N'[\d\w\s']*)$sourceRegEx(?=[\d\w\s']*',)", $destinstance
                    Write-Message -Message $sql -Level Debug
                    $destServer.Query($sql) | Out-Null
                    $destServer.Mail.Profiles.Refresh()
                    $copyMailProfileStatus.Status = "Successful"
                    $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                } catch {
                    $copyMailProfileStatus.Status = "Failed"
                    $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Issue copying mail profile $profileName to $destinstance | $PSItem"
                    continue
                }
            }
        }
    }

    function Copy-DbaDbMailServer {
        $sourceMailServers = $sourceServer.Mail.Accounts.MailServers
        $destMailServers = $destServer.Mail.Accounts.MailServers

        if (-not $ExcludePassword) {
            Write-Message -Message "Getting mail server credentials." -Level Verbose
            $sql = "SELECT credentials.name AS credential_name, sysmail_server.account_id FROM sys.credentials JOIN msdb.dbo.sysmail_server ON credentials.credential_id = sysmail_server.credential_id"
            $credentialAccounts = @($sourceServer.Query($sql))
            if ($credentialAccounts.Count -gt 0) {
                $decryptedCredentials = Get-DecryptedObject -SqlInstance $sourceServer -Credential $Credential -Type Credential -EnableException:$EnableException | Where-Object { $_.Name -in $credentialAccounts.credential_name }
            }
        }

        Write-Message -Message "Migrating mail servers." -Level Verbose
        foreach ($mailServer in $sourceMailServers) {
            $mailServerName = [string]$mailServer.name
            $copyMailServerStatus = [PSCustomObject]@{
                SourceServer      = $sourceServerName
                DestinationServer = $destServer.Name
                Name              = $mailServerName
                Type              = "Mail Server"
                Status            = $null
                Notes             = $null
                DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
            }
            if ($mailServers.count -gt 0 -and $mailServers -notcontains $mailServerName) {
                continue
            }

            if ($destMailServers.name -contains $mailServerName) {
                if ($force -eq $false) {
                    if ($__realCmdlet.ShouldProcess($destinstance, "Mail server $mailServerName exists at destination. Use -Force to drop and migrate.")) {
                        $copyMailServerStatus.Status = "Skipped"
                        $copyMailServerStatus.Notes = "Already exists on destination"
                        $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Message "Mail server $mailServerName exists at destination. Use -Force to drop and migrate." -Level Verbose
                    }
                    continue
                }

                If ($__realCmdlet.ShouldProcess($destinstance, "Dropping mail server $mailServerName and recreating.")) {
                    try {
                        Write-Message -Message "Dropping mail server $mailServerName." -Level Verbose
                        $destServer.Mail.Accounts.MailServers[$mailServerName].Drop()
                    } catch {
                        $copyMailServerStatus.Status = "Failed"
                        $copyMailServerStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Failed to drop and recreate mail server $mailServerName on $destinstance | $PSItem"
                        continue
                    }
                }
            }

            if ($__realCmdlet.ShouldProcess($destinstance, "Migrating account mail server $mailServerName.")) {
                try {
                    Write-Message -Message "Copying mail server $mailServerName." -Level Verbose
                    $sql = $mailServer.Script() | Out-String
                    $sql = $sql -replace "(?<=@account_name=N'[\d\w\s']*)$sourceRegEx(?=[\d\w\s']*',)", $destinstance
                    if (-not $ExcludePassword) {
                        $credentialName = ($credentialAccounts | Where-Object { $_.account_id -eq $mailServer.Parent.ID }).credential_name
                        if ($credentialName) {
                            $decryptedCred = $decryptedCredentials | Where-Object { $_.Name -eq $credentialName }
                            if ($decryptedCred) {
                                $password = $decryptedCred.Password.Replace("'", "''")
                                $sql = $sql -replace "@password=N''", "@password=N'$($password)'"
                            } else {
                                Write-Message -Level Warning -Message "Failed to get mail server password, it will need to be entered manually on the destination."
                            }
                        }
                    }
                    Write-Message -Message $sql -Level Debug
                    $destServer.Query($sql) | Out-Null
                    $copyMailServerStatus.Status = "Successful"
                    $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                } catch {
                    $copyMailServerStatus.Status = "Failed"
                    $copyMailServerStatus.Notes = (Get-ErrorMessage -Record $_)
                    $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Issue copying mail server $mailServerName on $destinstance | $PSItem"
                    continue
                }
            }
        }
    }

    try {
        # Do we need a dedicated admin connection to the source for password retrieval?
        # If passwords are excluded, we don't need a DAC
        if ($ExcludePassword) { $dacNeeded = $false } else { $dacNeeded = $true }

        # Do we have a dedicated admin connection already?
        $dacConnected = $Source.Type -eq 'Server' -and $Source.InputObject.Name -match '^ADMIN:'

        $dacOpened = $false
        if ($dacNeeded) {
            if ($dacConnected) {
                Write-Message -Level Verbose -Message "Reusing dedicated admin connection for password retrieval." -FunctionName Copy-DbaDbMail -ModuleName "dbatools"
                $sourceServer = $Source.InputObject
            } else {
                Write-Message -Level Verbose -Message "Opening dedicated admin connection for password retrieval." -FunctionName Copy-DbaDbMail -ModuleName "dbatools"
                $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9 -DedicatedAdminConnection -WarningAction SilentlyContinue
                $dacOpened = $true
            }
        } else {
            Write-Message -Level Verbose -Message "Opening or reusing normal connection because passwords are excluded." -FunctionName Copy-DbaDbMail -ModuleName "dbatools"
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
        }
        $sourceServerName = $sourceServer.DomainInstanceName
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Copy-DbaDbMail
        return
    }
    $mail = $sourceServer.mail
    $sourceRegEx = [RegEx]::Escape($Source)

    try {

    if (Test-FunctionInterrupt) { return }
    foreach ($destinstance in $Destination) {
        try {
            $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue -FunctionName Copy-DbaDbMail
        }

        if ($Type.Count -gt 0) {

            switch ($Type) {
                "ConfigurationValues" {
                    Copy-DbaDbMailConfig
                    $destServer.Mail.ConfigurationValues.Refresh()
                }

                "Profiles" {
                    Copy-DbaDbMailProfile
                    $destServer.Mail.Profiles.Refresh()
                }

                "Accounts" {
                    Copy-DbaDatabaseAccount
                    $destServer.Mail.Accounts.Refresh()
                }

                "mailServers" {
                    Copy-DbaDbMailServer
                }
            }

            continue
        }

        if (($profiles.count + $accounts.count + $mailServers.count) -gt 0) {

            if ($profiles.count -gt 0) {
                Copy-DbaDbMailProfile -Profiles $profiles
                $destServer.Mail.Profiles.Refresh()
            }

            if ($accounts.count -gt 0) {
                Copy-DbaDatabaseAccount -Accounts $accounts
                $destServer.Mail.Accounts.Refresh()
            }

            if ($mailServers.count -gt 0) {
                Copy-DbaDbMailServer -mailServers $mailServers
            }

            continue
        }

        Copy-DbaDbMailConfig
        $destServer.Mail.ConfigurationValues.Refresh()
        Copy-DbaDatabaseAccount
        $destServer.Mail.Accounts.Refresh()
        Copy-DbaDbMailProfile
        $destServer.Mail.Profiles.Refresh()
        Copy-DbaDbMailServer

        # Check Database Mail configuration on source and destination
        $sourceDbMailConfig = Get-DbaSpConfigure -SqlInstance $sourceServer -Name "Database Mail XPs"
        $destDbMailConfig = Get-DbaSpConfigure -SqlInstance $destServer -Name "Database Mail XPs"

        $sourceDbMailEnabled = $sourceDbMailConfig.ConfiguredValue
        $destDbMailEnabled = $destDbMailConfig.ConfiguredValue

        Write-Message -Message "Source Database Mail XPs: $sourceDbMailEnabled" -Level Verbose -FunctionName Copy-DbaDbMail -ModuleName "dbatools"
        Write-Message -Message "Destination Database Mail XPs: $destDbMailEnabled" -Level Verbose -FunctionName Copy-DbaDbMail -ModuleName "dbatools"

        $enableDBMailStatus = [PSCustomObject]@{
            SourceServer      = $sourceServerName
            DestinationServer = $destServer.Name
            Name              = "Database Mail XPs"
            Type              = "Mail Configuration"
            Status            = $null
            Notes             = $null
            DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
        }

        if ($sourceDbMailEnabled -eq 1 -and $destDbMailEnabled -eq 0) {
            if ($__realCmdlet.ShouldProcess($destinstance, "Enabling Database Mail XPs")) {
                try {
                    Write-Message -Message "Enabling Database Mail XPs on $destServer." -Level Verbose -FunctionName Copy-DbaDbMail -ModuleName "dbatools"
                    $null = Set-DbaSpConfigure -SqlInstance $destServer -Name "Database Mail XPs" -Value 1
                    $enableDBMailStatus.Status = "Successful"
                    $enableDBMailStatus.Notes = "Database Mail XPs enabled on destination"
                } catch {
                    $enableDBMailStatus.Status = "Failed"
                    $enableDBMailStatus.Notes = (Get-ErrorMessage -Record $_)
                    Write-Message -Level Warning -Message "Cannot enable Database Mail XPs on $destinstance | $PSItem" -FunctionName Copy-DbaDbMail -ModuleName "dbatools"
                }
                $enableDBMailStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
        } elseif ($sourceDbMailEnabled -eq 0) {
            $enableDBMailStatus.Status = "Skipped"
            $enableDBMailStatus.Notes = "Database Mail XPs not enabled on source"
            Write-Message -Level Warning -Message "Database Mail XPs is not enabled on source instance $sourceServer. It will not be enabled on destination." -FunctionName Copy-DbaDbMail -ModuleName "dbatools"
            $enableDBMailStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
        } elseif ($destDbMailEnabled -eq 1) {
            $enableDBMailStatus.Status = "Skipped"
            $enableDBMailStatus.Notes = "Database Mail XPs already enabled on destination"
            Write-Message -Message "Database Mail XPs is already enabled on destination $destServer." -Level Verbose -FunctionName Copy-DbaDbMail -ModuleName "dbatools"
            $enableDBMailStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
        }
    }

    } finally {
        if ($dacOpened) {
            $null = $sourceServer | Disconnect-DbaInstance -WhatIf:$false
        }
    }
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $Credential $Type $ExcludePassword $Force $EnableException $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
