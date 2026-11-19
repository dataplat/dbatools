#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies database certificates from a source SQL Server instance to one or more destinations.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that certificate discovery,
/// the backup and restore round-trip, master-key handling, the migration status objects, and dbatools
/// stream and error handling stay observable-identical to the script implementation.
/// </para>
/// <para>
/// The command takes no pipeline input, so it ships as TWO hops to preserve the script's lifecycle:
/// a BeginProcessing hop connects the source, gathers the source certificates and the derived backup
/// password EXACTLY ONCE - so it still runs when the upstream pipeline is empty, matching the function
/// - and a ProcessRecord hop copies to each destination. The source certificates, their database
/// names, the source server, and the backup encryption password are carried between the hops as
/// fields. The backup password in particular MUST be carried: it is a once-generated random password
/// (when none is supplied), and re-deriving it per record would restore with a different password
/// than the backup used. The ProcessRecord hop copies to each destination database in turn, emitting a
/// result object per copy, and can raise a terminating -EnableException failure on a later copy after an
/// earlier one has already emitted, so its output is streamed through InvokeScopedStreaming - each result
/// reaches the pipeline as produced and survives a later throw; a buffered collection would be discarded
/// on that throw and lose the earlier copies' results.
/// </para>
/// <para>
/// The encryption and decryption passwords ride into the hop as live SecureStrings and are handed to
/// the nested Backup-DbaDbCertificate and Restore-DbaDbCertificate calls, which perform any conversion
/// inside their own ShouldProcess-gated bodies; this command's own gate wraps the whole copy.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Copy, "DbaDbCertificate", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Default")]
public sealed class CopyDbaDbCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for the destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>The database or databases whose certificates are copied.</summary>
    [Parameter(Position = 4)]
    public string[]? Database { get; set; }

    /// <summary>Databases to exclude.</summary>
    [Parameter(Position = 5)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>The certificate name or names to copy.</summary>
    [Parameter(Position = 6)]
    public string[]? Certificate { get; set; }

    /// <summary>Certificates to exclude.</summary>
    [Parameter(Position = 7)]
    public string[]? ExcludeCertificate { get; set; }

    /// <summary>A network path readable by both the source and destination service accounts.</summary>
    [Parameter(Position = 8)]
    public string? SharedPath { get; set; }

    /// <summary>The password used to create a destination database master key when one is missing.</summary>
    [Parameter(Position = 9)]
    public System.Security.SecureString? MasterKeyPassword { get; set; }

    /// <summary>The password used to encrypt the exported certificate during the copy.</summary>
    [Parameter(Position = 10)]
    public System.Security.SecureString? EncryptionPassword { get; set; }

    /// <summary>The password used to decrypt the source certificate's private key.</summary>
    [Parameter(Position = 11)]
    public System.Security.SecureString? DecryptionPassword { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Set when the begin block stopped the command (source failure or shared-path access).</summary>
    private bool _beginInterrupted;

    /// <summary>State gathered once in begin and read by each record.</summary>
    private object? _sourceCertificates;
    private object? _dbsNames;
    private object? _sourceServer;
    private object? _backupEncryptionPassword;

    /// <summary>Connects the source and gathers the certificates and backup password once.</summary>
    protected override void BeginProcessing()
    {
        bool completed = false;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Source, SourceSqlCredential, Database, ExcludeDatabase, Certificate, ExcludeCertificate,
            SharedPath, EncryptionPassword, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__CopyDbaDbCertificateBeginComplete"]?.Value))
            {
                completed = true;
                _sourceCertificates = Unwrap(item.Properties["SourceCertificates"]?.Value);
                _dbsNames = Unwrap(item.Properties["DbsNames"]?.Value);
                _sourceServer = Unwrap(item.Properties["SourceServer"]?.Value);
                _backupEncryptionPassword = Unwrap(item.Properties["BackupEncryptionPassword"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }

        // The sentinel is the last statement of the begin body, so it is absent exactly when that
        // body returned early - which it does only after a source failure or a shared-path access stop.
        _beginInterrupted = !completed;
    }

    /// <summary>Copies the source certificates to each destination for one record.</summary>
    protected override void ProcessRecord()
    {
        if (_beginInterrupted || Interrupted)
            return;

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
        }, ProcessScript,
            Destination, DestinationSqlCredential, SharedPath, MasterKeyPassword, DecryptionPassword,
            _sourceCertificates, _dbsNames, _sourceServer, _backupEncryptionPassword,
            EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    /// <summary>
    /// Unwraps a value the begin hop carried out through its sentinel.
    /// </summary>
    /// <remarks>
    /// A filter that matched nothing leaves the script variable holding AutomationNull, which behaves
    /// as $null in PowerShell but unwraps to a truthy, property-less object - so it comes back as null
    /// instead, and the process replay sees the emptiness the script saw. Otherwise the value is
    /// unwrapped ONLY when the wrapper adds nothing: note properties (whether Add-Member decoration on
    /// an SMO object or the members of a [PSCustomObject]) live on the PSObject wrapper rather than the
    /// BaseObject, so unwrapping such a value silently discards them.
    /// </remarks>
    private static object? Unwrap(object? value)
    {
        if (value is null || ReferenceEquals(value, System.Management.Automation.Internal.AutomationNull.Value))
            return null;
        if (value is not PSObject wrapper)
            return value;
        foreach (PSMemberInfo member in wrapper.Members)
        {
            if (member is PSNoteProperty)
                return wrapper;
        }
        return wrapper.BaseObject;
    }

    // PS: the begin body VERBATIM. Substitution only: -FunctionName on the two direct Stop-Function
    // calls. Both keep their explicit return, which skips the trailing sentinel - that absence is how
    // BeginProcessing learns the begin stopped. The gathered source certificates, database names,
    // source server, and the derived backup password are emitted through the sentinel for the process
    // hop (a hop scope dies between hops). The "$PSBoundParameter.EncryptionPassword" reference is
    // reproduced verbatim - it is a source typo (singular, not the $PSBoundParameters automatic
    // variable), so it is always null and a random backup password is always generated.
    private const string BeginScript = """
param($Source, $SourceSqlCredential, $Database, $ExcludeDatabase, $Certificate, $ExcludeCertificate, $SharedPath, $EncryptionPassword, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, [PSCredential]$SourceSqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [string[]]$Certificate, [string[]]$ExcludeCertificate, [string]$SharedPath, [Security.SecureString]$EncryptionPassword, $EnableException, $__boundVerbose, $__boundDebug)

    try {
        $parms = @{
            SqlInstance     = $Source
            SqlCredential   = $SourceSqlCredential
            Database        = $Database
            ExcludeDatabase = $ExcludeDatabase
            Certificate     = $Certificate
            EnableException = $true
        }
        # Get presumably user certs, no way to tell if its a system object
        $sourcecertificates = Get-DbaDbCertificate @parms | Where-Object { $PSItem.Name -notlike "#*" -and $PSItem.Name -notin $ExcludeCertificate }
        $dbsnames = $sourcecertificates.Parent.Name | Select-Object -Unique
        $server = ($sourcecertificates | Select-Object -First 1).Parent.Parent
        $serviceAccount = $server.ServiceAccount
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $PSItem -Target $Source -FunctionName Copy-DbaDbCertificate
        return
    }

    if (-not $PSBoundParameter.EncryptionPassword) {
        $backupEncryptionPassword = Get-RandomPassword
    } else {
        $backupEncryptionPassword = $EncryptionPassword
    }

    If ($serviceAccount -and -not (Test-DbaPath -SqlInstance $Source -SqlCredential $SourceSqlCredential -Path $SharedPath)) {
        Stop-Function -Message "The SQL Server service account ($serviceAccount) for $Source does not have access to $SharedPath" -FunctionName Copy-DbaDbCertificate
        return
    }

    # The two collections are normalized with @() so the seam carries cardinality unambiguously: a
    # filter that matched nothing becomes an empty array rather than AutomationNull, which the process
    # replay would otherwise receive as a truthy, property-less object and iterate over.
    [pscustomobject]@{ __CopyDbaDbCertificateBeginComplete = $true; SourceCertificates = @($sourcecertificates); DbsNames = @($dbsnames); SourceServer = $server; BackupEncryptionPassword = $backupEncryptionPassword }
} $Source $SourceSqlCredential $Database $ExcludeDatabase $Certificate $ExcludeCertificate $SharedPath $EncryptionPassword $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet and -FunctionName
    // on the direct Stop-Function/Write-Message calls (no nested named helper). $sourcecertificates,
    // $dbsnames, $server and $backupEncryptionPassword arrive from the begin hop; the process
    // Test-FunctionInterrupt guard is preserved verbatim (the begin stop is carried by
    // _beginInterrupted, so this record only runs when begin completed). The "$cername" reference in
    // a Verbose message is a source typo (should be $certname) and is reproduced as-is.
    private const string ProcessScript = """
param($Destination, $DestinationSqlCredential, $SharedPath, $MasterKeyPassword, $DecryptionPassword, $sourcecertificates, $dbsnames, $server, $backupEncryptionPassword, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, [PSCredential]$DestinationSqlCredential, [string]$SharedPath, [Security.SecureString]$MasterKeyPassword, [Security.SecureString]$DecryptionPassword, $sourcecertificates, $dbsnames, $server, $backupEncryptionPassword, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (Test-FunctionInterrupt) { return }
    foreach ($destinstance in $Destination) {
        try {
            $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $PSItem -Target $destinstance -Continue -FunctionName Copy-DbaDbCertificate
        }
        $serviceAccount = $destserver.ServiceAccount

        If (-not (Test-DbaPath -SqlInstance $destServer -Path $SharedPath)) {
            Stop-Function -Message "The SQL Server service account ($serviceAccount) for $destinstance does not have access to $SharedPath" -Continue -FunctionName Copy-DbaDbCertificate
        }

        if (($sourcecertificates | Where-Object PrivateKeyEncryptionType -eq MasterKey)) {
            $masterkey = Get-DbaDbMasterKey -SqlInstance $destServer -Database master
            if (-not $masterkey) {
                Write-Message -Level Verbose -Message "master key not found, seeing if MasterKeyPassword was specified" -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"
                if ($MasterKeyPassword) {
                    Write-Message -Level Verbose -Message "master key not found, creating one" -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"
                    try {
                        $params = @{
                            SqlInstance     = $destServer
                            SecurePassword  = $MasterKeyPassword
                            Database        = "master"
                            EnableException = $true
                        }
                        $masterkey = New-DbaDbMasterKey @params
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $PSItem -Continue -FunctionName Copy-DbaDbCertificate
                    }
                } else {
                    Stop-Function -Message "Master service key not found on $destinstance and MasterKeyPassword not specified, so it cannot be created" -Continue -FunctionName Copy-DbaDbCertificate
                }
            }
            $null = $destServer.Databases["master"].Refresh()
        }

        $destdbs = $destServer.Databases | Where-Object Name -in $dbsnames

        foreach ($db in $destdbs) {
            $dbName = $db.Name
            $sourcerts = $sourcecertificates | Where-Object { $PSItem.Parent.Name -eq $db.Name }

            # Check for master key requirement
            if (($sourcerts | Where-Object PrivateKeyEncryptionType -eq MasterKey)) {
                $masterkey = Get-DbaDbMasterKey -SqlInstance $db.Parent -Database $db.Name

                if (-not $masterkey) {
                    Write-Message -Level Verbose -Message "Master key not found, seeing if MasterKeyPassword was specified" -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"
                    if ($MasterKeyPassword) {
                        try {
                            $params = @{
                                SqlInstance     = $destServer
                                SecurePassword  = $MasterKeyPassword
                                Database        = $db.Name
                                EnableException = $true
                            }
                            $masterkey = New-DbaDbMasterKey @params
                            $domasterkeymessage = $false
                            $domasterkeypasswordmessage = $false
                        } catch {
                            $domasterkeymessage = "Master key auto-generation failure: $PSItem"
                            Stop-Function -Message "Failure" -ErrorRecord $PSItem -Continue -FunctionName Copy-DbaDbCertificate
                        }

                    } else {
                        $domasterkeypasswordmessage = $true
                    }
                }

                foreach ($cert in $sourcerts) {
                    $certname = $cert.Name
                    Write-Message -Level VeryVerbose -Message "Processing $certname on $dbName" -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"

                    $copyDbCertificateStatus = [PSCustomObject]@{
                        SourceServer          = $cert.Parent.Parent.Name
                        SourceDatabase        = $dbName
                        SourceDatabaseID      = $cert.Parent.ID
                        DestinationServer     = $destServer.Name
                        DestinationDatabase   = $dbName
                        DestinationDatabaseID = $db.ID
                        type                  = "Database Certificate"
                        Name                  = $certname
                        Status                = $null
                        Notes                 = $null
                        DateTime              = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                    }

                    if ($domasterkeymessage) {
                        if ($__realCmdlet.ShouldProcess($destServer.Name, $domasterkeymessage)) {
                            $copyDbCertificateStatus.Status = "Skipped"
                            $copyDbCertificateStatus.Notes = $domasterkeymessage
                            $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message $domasterkeymessage -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"
                        }
                        continue
                    }

                    if ($domasterkeypasswordmessage) {
                        if ($__realCmdlet.ShouldProcess($destServer.Name, "Master service key not found and MasterKeyPassword not provided for auto-creation")) {
                            $copyDbCertificateStatus.Status = "Skipped"
                            $copyDbCertificateStatus.Notes = "Master service key not found and MasterKeyPassword not provided for auto-creation"
                            $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Master service key not found and MasterKeyPassword not provided for auto-creation" -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"
                        }
                        continue
                    }
                    $null = $db.Refresh()
                    if ($db.Certificates.Name -contains $certname) {
                        if ($__realCmdlet.ShouldProcess($destServer.Name, "Certificate $certname exists at destination in the $dbName database")) {
                            $copyDbCertificateStatus.Status = "Skipped"
                            $copyDbCertificateStatus.Notes = "Already exists on destination"
                            $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Certificate $certname exists at destination in the $dbName database" -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"
                        }
                        continue
                    }

                    if ($__realCmdlet.ShouldProcess($destServer.Name, "Copying certificate $certname from database.")) {
                        try {
                            # Back up certificate
                            $null = $db.Refresh()
                            $params = @{
                                SqlInstance        = $cert.Parent.Parent
                                Database           = $db.Name
                                Certificate        = $certname
                                Path               = $SharedPath
                                EnableException    = $true
                                EncryptionPassword = $backupEncryptionPassword
                                DecryptionPassword = $DecryptionPassword
                            }
                            Write-Message -Level Verbose -Message "Backing up certificate $cername for $($dbName) on $($server.Name)" -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"
                            try {
                                $tempPath = Join-DbaPath -SqlInstance $server -Path $SharedPath -ChildPath "$certname.cer"
                                $tempKey = Join-DbaPath -SqlInstance $server -Path $SharedPath -ChildPath "$certname.pvk"

                                if ((Test-DbaPath -SqlInstance $server -Path $tempPath) -and (Test-DbaPath -SqlInstance $server -Path $tempKey)) {
                                    $export = [PSCustomObject]@{
                                        Path = Join-DbaPath -SqlInstance $server -Path $SharedPath -ChildPath "$certname.cer"
                                        Key  = Join-DbaPath -SqlInstance $server -Path $SharedPath -ChildPath "$certname.pvk"
                                    }
                                    # if files exist, then try to be helpful, otherwise, it just kills the whole process
                                    # this workaround exists because if you rename the back file, you'll rename the cert on restore
                                    Write-Message -Level Verbose -Message "ATTEMPTING TO USE FILES THAT ALREADY EXIST: $tempPath and $tempKey" -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"
                                    $usingtempfiles = $true
                                } else {
                                    $export = Backup-DbaDbCertificate @params

                                    # The exported files are only readable by the source instance account
                                    # But for the restore they need to be readable by the targe instance account
                                    # Current solution is to try to make them readable to everyone and remove them after the restore
                                    foreach ($filePath in $export.Path, $export.Key) {
                                        try {
                                            $acl = Get-Acl $filePath
                                            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "ReadAndExecute", "None", "None", "Allow")
                                            $acl.SetAccessRule($accessRule)
                                            Set-Acl -Path $filePath -AclObject $acl
                                        } catch {
                                            Write-Message -Level Verbose -Message "Failed to set permission for [$filePath]: $_" -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"
                                        }
                                    }
                                }
                            } catch {
                                $copyDbCertificateStatus.Status = "Failed $PSItem"
                                $copyDbCertificateStatus.Notes = $PSItem
                                $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Failed to create certificate $certname for $dbName on $destinstance | $PSItem" -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"
                                continue
                            }

                            # Restore certificate
                            $params = @{
                                SqlInstance        = $db.Parent
                                Database           = $db.Name
                                Name               = $export.Certificate
                                Path               = $export.Path
                                KeyFilePath        = $export.Key
                                EnableException    = $true
                                EncryptionPassword = $DecryptionPassword
                                DecryptionPassword = $backupEncryptionPassword
                            }

                            $null = Restore-DbaDbCertificate @params
                            $copyDbCertificateStatus.Status = "Successful"
                            $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        } catch {
                            $copyDbCertificateStatus.Status = "Failed"
                            $copyDbCertificateStatus.Notes = $PSItem
                            $copyDbCertificateStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            if ($usingtempfiles) {
                                Write-Message -Level Verbose -Message "Issue creating certificate $certname from $($export.Path) for $dbname on $($db.Parent.Name). Note that $($export.Path) and $($export.Key) already existed so we tried to use them. If this is an issue, please move or rename both files and try again." -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"
                            } else {
                                Write-Message -Level Verbose -Message "Issue creating certificate $certname from $($export.Path) for $dbname on $($db.Parent.Name) | $PSItem" -FunctionName Copy-DbaDbCertificate -ModuleName "dbatools"
                            }
                        } finally {
                            if ($export.Path -and -not $usingtempfiles) {
                                $null = Remove-Item -Path $export.Path -Force -ErrorAction SilentlyContinue
                            }
                            if ($export.Key -and -not $usingtempfiles) {
                                $null = Remove-Item -Path $export.Key -Force -ErrorAction SilentlyContinue
                            }
                        }
                    }
                }
            }
        }
    }
} $Destination $DestinationSqlCredential $SharedPath $MasterKeyPassword $DecryptionPassword $sourcecertificates $dbsnames $server $backupEncryptionPassword $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

