#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports database master keys to password-protected key files on one or more SQL Server instances.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that database discovery, the
/// SMO export call, path handling, the output decoration, and dbatools stream and error handling
/// stay observable-identical to the script implementation.
/// </para>
/// <para>
/// The script's begin block only substituted the credential's password for the SecurePassword; that
/// deterministic substitution is done here in C# (the SecureString is never converted to plain text),
/// so the command needs a single process hop. The export password rides into the hop as a live
/// SecureString and is turned into plain text only at the SMO export call, and only inside the
/// ShouldProcess gate - so -WhatIf never materializes a plain-text password.
/// </para>
/// </remarks>
[Cmdlet(VerbsData.Backup, "DbaDbMasterKey", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class BackupDbaDbMasterKeyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>A credential whose password is used to encrypt the exported master key.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>The database or databases whose master keys are exported.</summary>
    [Parameter(Position = 3)]
    public string[]? Database { get; set; }

    /// <summary>Databases to exclude from the export.</summary>
    [Parameter(Position = 4)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>The password that encrypts the exported master key.</summary>
    [Parameter(Position = 5)]
    [Alias("Password")]
    public System.Security.SecureString? SecurePassword { get; set; }

    /// <summary>The directory the exported files are written to; defaults to the instance backup directory.</summary>
    [Parameter(Position = 6)]
    public string? Path { get; set; }

    /// <summary>An explicit base file name for the exported key file.</summary>
    [Parameter(Position = 7)]
    public string? FileBaseName { get; set; }

    /// <summary>Database objects, typically piped from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 8)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    private System.Security.SecureString? _promptedSecurePassword;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Exports the master keys for one pipeline record.</summary>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // PS begin: "if ($Credential) { $SecurePassword = $Credential.Password }". A bound Credential
        // replaces SecurePassword outright, even if its password is empty - so this is a ternary on
        // whether Credential was supplied, never a null-coalesce on the value. The SecureString is
        // passed on as-is; it is not converted here.
        System.Security.SecureString? effectivePassword = Credential != null
            ? Credential.Password
            : SecurePassword ?? _promptedSecurePassword;

        // [DEF-001] streamed via InvokeScopedStreaming: the hop body loops emitting per-item and
        // carries reachable terminating throws (-Continue Stop-Function under -EnableException), so a
        // buffered InvokeScoped would lose an earlier item's emit when a later item throws. Streaming
        // yields each record as produced. The command-specific sentinel carries a password entered
        // interactively in the hop so later pipeline records reuse the source function's answer.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__backupDbaDbMasterKeyProcess"))
            {
                if (sentinel["__backupDbaDbMasterKeyProcess"] is Hashtable state &&
                    state["SecurePassword"] is System.Security.SecureString promptedSecurePassword)
                {
                    _promptedSecurePassword = promptedSecurePassword;
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Credential, Database, ExcludeDatabase, effectivePassword,
            Path, FileBaseName, InputObject, EnableException.ToBool(), this,
            TestBound(nameof(Path)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM per record. The begin credential-to-password substitution
    // is applied in C# (effectivePassword), so the hop receives $SecurePassword already resolved.
    // Substitutions only: $Pscmdlet -> $__realCmdlet; "Test-Bound -ParameterName Path -Not" -> the
    // carried "-not $__boundPath" flag (Test-Bound inspects the caller's bound parameters and cannot
    // ride a hop); and -FunctionName on the direct Stop-Function/Write-Message calls. The Read-Host
    // prompt path is preserved verbatim - it is only reached when neither a password nor a credential
    // is supplied, exactly as in the source, and is not exercised by the tests.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Credential, $Database, $ExcludeDatabase, $SecurePassword, $Path, $FileBaseName, $InputObject, $EnableException, $__realCmdlet, $__boundPath, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [PSCredential]$Credential, [string[]]$Database, [string[]]$ExcludeDatabase, [Security.SecureString]$SecurePassword, [string]$Path, [string]$FileBaseName, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__boundPath, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
    }

    foreach ($db in $InputObject) {
        $dbname = $db.Name
        $server = $db.Parent
        $instance = $server.Name

        if (-not $__boundPath) {
            $Path = $server.BackupDirectory
        }

        if (-not $Path) {
            Stop-Function -Message "Path discovery failed. Please explicitly specify -Path" -Target $server -Continue -FunctionName Backup-DbaDbMasterKey
        }

        if (-not (Test-DbaPath -SqlInstance $server -Path $Path)) {
            Stop-Function -Message "$instance cannot access $Path" -Target $server -Continue -FunctionName Backup-DbaDbMasterKey
        }

        $actualPath = "$Path".TrimEnd('\').TrimEnd('/')

        if (-not $db.IsAccessible) {
            Write-Message -Level Warning -Message "Database $db is not accessible. Skipping." -FunctionName Backup-DbaDbMasterKey -ModuleName "dbatools"
            continue
        }

        $masterkey = $db.MasterKey

        if (-not $masterkey) {
            Write-Message -Message "No master key exists in the $dbname database on $instance" -Target $db -Level Verbose -FunctionName Backup-DbaDbMasterKey -ModuleName "dbatools"
            continue
        }

        # If you pass a password param, then you will not be prompted for each database, but it wouldn't be a good idea to build in insecurity
        if (-not $SecurePassword -and -not $Credential) {
            $SecurePassword = Read-Host -AsSecureString -Prompt "You must enter Service Key password for $instance"
            $SecurePassword2 = Read-Host -AsSecureString -Prompt "Type the password again"

            if (($SecurePassword | ConvertFrom-SecurePass) -ne ($SecurePassword2 | ConvertFrom-SecurePass)) {
                Stop-Function -Message "Passwords do not match" -Continue -FunctionName Backup-DbaDbMasterKey
            }
        }


        if (-not (Test-DbaPath -SqlInstance $server -Path $actualPath)) {
            Stop-Function -Message "$SqlInstance cannot access $actualPath" -Target $actualPath -FunctionName Backup-DbaDbMasterKey
        }

        $fileinstance = $instance.ToString().Replace('\', '$')
        $targetBaseName = "$fileinstance-$dbname-masterkey"
        if ($FileBaseName) {
            $targetBaseName = $FileBaseName
        }

        $exportFileName = Join-DbaPath -SqlInstance $server -Path $actualPath -ChildPath "$targetBaseName.key"

        # if the base file name exists, then default to old style of appending a timestamp
        if (Test-DbaPath -SqlInstance $server -Path $exportFileName) {
            $time = Get-Date -Format yyyMMddHHmmss
            $exportFileName = Join-DbaPath -SqlInstance $server -Path $actualPath -ChildPath "$targetBaseName-$time.key"
            # Sleep for a second to avoid another export in the same second
            Start-Sleep -Seconds 1
        }

        if ($__realCmdlet.ShouldProcess($instance, "Backing up master key to $exportFileName")) {
            try {
                $masterkey.Export($exportFileName, ($SecurePassword | ConvertFrom-SecurePass))
                $status = "Success"
            } catch {
                $status = "Failure"
                Write-Message -Level Warning -Message "Backup failure: $($_.Exception.InnerException)" -FunctionName Backup-DbaDbMasterKey -ModuleName "dbatools"
            }

            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Database -value $dbName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name DatabaseID -value $db.ID
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Filename -value $exportFileName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Status -value $status

            Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, Database, 'Filename as Path', Status
        }
    }
    @{ __backupDbaDbMasterKeyProcess = @{ SecurePassword = $SecurePassword } }
} $SqlInstance $SqlCredential $Credential $Database $ExcludeDatabase $SecurePassword $Path $FileBaseName $InputObject $EnableException $__realCmdlet $__boundPath $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
