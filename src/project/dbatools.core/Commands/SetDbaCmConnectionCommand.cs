#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.Management.Infrastructure.Options;

namespace Dataplat.Dbatools.Commands;

/// <summary>Configures remote computer connection settings for SQL Server host management.</summary>
/// <para>
/// Configures connection objects that dbatools uses to manage remote SQL Server host computers via CIM, WMI, and PowerShell remoting.
/// This function creates new connection records for computers not yet cached, or modifies existing connection settings for previously contacted hosts.
/// </para>
/// <para>
/// Use this to bulk-configure connection behavior, manage credential caching, or troubleshoot remote connection issues when dbatools functions need to access SQL Server host systems for tasks like service management, file operations, or system information gathering.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCmConnection sql2014 | Set-DbaCmConnection -ClearBadCredential -UseWindowsCredentials
/// </code>
/// <para>
/// Retrieves the already existing connection to sql2014, removes the list of not working credentials and configures it to default to the credentials of the logged on user.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCmConnection | Set-DbaCmConnection -RemoveBadCredential $cred
/// </code>
/// <para>
/// Removes the credentials stored in $cred from all connections' list of "known to not work" credentials.
/// Handy to update changes in privilege.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCmConnection | Export-Clixml .\connections.xml
/// PS C:\&gt; Import-Clixml .\connections.xml | Set-DbaCmConnection -ResetConfiguration
/// </code>
/// <para>
/// At first, the current cached connections are stored in an xml file. At a later time - possibly in the profile when starting the console again - those connections are imported again and applied again to the connection cache.
/// </para>
/// <para>
/// In this example, the configuration settings will also be reset, since after re-import those will be set to explicit, rather than deriving them from the global settings.
/// In many cases, using the default settings is desirable. For specific settings, use New-DbaCmConnection as part of the profile in order to explicitly configure a connection.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item><term>OUTPUTS</term><description>
/// <para>
/// Dataplat.Dbatools.Connection.ManagementConnection
/// </para>
/// <para>
/// Returns the modified connection object after applying the specified configuration changes. The object represents the remote computer connection settings used by dbatools for CIM, WMI, and PowerShell remoting operations.
/// </para>
/// <para>
/// Default display properties:
/// - ComputerName: The name of the SQL Server host computer for which connection settings were configured
/// - IsConnected: Boolean indicating whether a successful connection to the remote computer has been established
/// - CimRM: Current status of CIM (WinRM) connectivity (Unknown, Connected, Failed, Untested)
/// - CimDCOM: Current status of CIM (DCOM) connectivity (Unknown, Connected, Failed, Untested)
/// - Wmi: Current status of WMI connectivity (Unknown, Connected, Failed, Untested)
/// - PowerShellRemoting: Current status of PowerShell remoting connectivity (Unknown, Connected, Failed, Untested)
/// </para>
/// <para>
/// Additional properties available (from ManagementConnection object):
/// - Credentials: Currently cached credentials for this connection
/// - UseWindowsCredentials: Boolean indicating whether Windows credentials of the current user are configured
/// - WindowsCredentialsAreBad: Boolean indicating whether Windows credentials have been marked as non-functional
/// - KnownBadCredentials: Collection of credentials known to fail authentication
/// - OverrideExplicitCredential: Boolean indicating whether cached credentials override explicit parameters
/// - OverrideConnectionPolicy: Boolean indicating whether global connection policies are bypassed
/// - DisabledConnectionTypes: Connection protocols disabled for this computer
/// - DisableBadCredentialCache: Boolean indicating whether failed credentials are cached
/// - DisableCimPersistence: Boolean indicating whether CIM sessions are recreated each time
/// - DisableCredentialAutoRegister: Boolean indicating whether successful credentials are auto-cached
/// - EnableCredentialFailover: Boolean indicating whether credential failover is enabled
/// - CimWinRMOptions: WinRM session options for CIM connections
/// - CimDCOMOptions: DCOM session options for CIM connections
/// - LastCimRM: DateTime of last CIM (WinRM) connection attempt
/// - LastCimDCOM: DateTime of last CIM (DCOM) connection attempt
/// - LastWmi: DateTime of last WMI connection attempt
/// - LastPowerShellRemoting: DateTime of last PowerShell remoting connection attempt
/// </para>
/// </description></item>
/// <item><term /><description>
/// <para>
/// Tags: ComputerManagement, CIM
/// Author: Friedrich Weinmann (@FredWeinmann)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description></item>
/// </list>
/// <seealso href="https://dbatools.io/Set-DbaCmConnection" />
[Cmdlet(VerbsCommon.Set, "DbaCmConnection", SupportsShouldProcess = true, DefaultParameterSetName = "Credential")]
public sealed class SetDbaCmConnectionCommand : DbaBaseCmdlet
{
    /// <para>
    /// Specifies the SQL Server host computer name to configure connection settings for. Accepts computer names, FQDNs, or IP addresses.
    /// Use this when you need to pre-configure how dbatools connects to specific SQL Server host machines for service management, file operations, or system administration tasks.
    /// </para>
    [Parameter(ValueFromPipeline = true)]
    public DbaCmConnectionParameter[]? ComputerName { get; set; }

    /// <para>
    /// The credential to register.
    /// </para>
    [Parameter(ParameterSetName = "Credential")]
    public PSCredential? Credential { get; set; }

    /// <para>
    /// Confirms that Windows credentials of the current user should be used for remote connections to the target computer.
    /// Set this when you know the current user account has sufficient privileges on the remote SQL Server host and want to avoid credential prompts.
    /// </para>
    [Parameter(ParameterSetName = "Windows")]
    public SwitchParameter UseWindowsCredentials { get; set; }

    /// <para>
    /// Forces dbatools to use cached working credentials instead of explicitly provided credentials when available.
    /// Enable this when you want the connection system to automatically use known-good credentials rather than failing with explicitly provided but incorrect credentials.
    /// </para>
    [Parameter]
    public SwitchParameter OverrideExplicitCredential { get; set; }

    /// <para>
    /// Allows this connection to bypass global connection type restrictions configured in dbatools settings.
    /// Use this when you need to enable specific connection methods (CIM, WMI, PowerShell remoting) for individual computers that are normally disabled globally.
    /// </para>
    [Parameter]
    public SwitchParameter OverrideConnectionPolicy { get; set; }

    /// <para>
    /// Specifies which connection protocols to disable for this computer (CIM, WMI, PowerShell remoting, or combinations).
    /// Use this to block problematic connection methods on specific hosts while allowing others to work normally.
    /// </para>
    [Parameter]
    public ManagementConnectionType DisabledConnectionTypes { get; set; } = ManagementConnectionType.None;

    /// <para>
    /// Prevents dbatools from remembering credentials that fail authentication for this computer.
    /// Enable this when you're frequently changing credentials or troubleshooting authentication issues and don't want failed attempts cached.
    /// </para>
    [Parameter]
    public SwitchParameter DisableBadCredentialCache { get; set; }

    /// <para>
    /// Forces dbatools to create new CIM sessions for each operation instead of reusing existing sessions.
    /// Use this when experiencing issues with persistent CIM connections or when you need fresh authentication for each operation.
    /// </para>
    [Parameter]
    public SwitchParameter DisableCimPersistence { get; set; }

    /// <para>
    /// Prevents successful credentials from being automatically saved to the connection cache for future use.
    /// Enable this for security-sensitive environments where you don't want credentials stored in memory between operations.
    /// </para>
    [Parameter]
    public SwitchParameter DisableCredentialAutoRegister { get; set; }

    /// <para>
    /// Allows dbatools to automatically try previously successful credentials when the provided credentials fail.
    /// Use this to improve connection reliability by falling back to known working credentials when new ones don't authenticate properly.
    /// </para>
    [Parameter]
    public SwitchParameter EnableCredentialFailover { get; set; }

    /// <para>
    /// Marks the current user's Windows credentials as non-functional for this remote computer.
    /// Set this when you know Windows authentication won't work for the target host and want to prevent automatic attempts with current user credentials.
    /// </para>
    [Parameter(ParameterSetName = "Credential")]
    public SwitchParameter WindowsCredentialsAreBad { get; set; }

    /// <para>
    /// Specifies advanced WinRM session options for CIM connections, such as authentication methods, timeouts, or proxy settings.
    /// Create this object using New-CimSessionOption and use when you need custom WinRM configuration for challenging network environments.
    /// </para>
    [Parameter]
    public WSManSessionOptions? CimWinRMOptions { get; set; }

    /// <para>
    /// Specifies advanced DCOM session options for CIM connections, including authentication, impersonation levels, or DCOM-specific settings.
    /// Create this object using New-CimSessionOption and use when connecting through firewalls or when WinRM isn't available.
    /// </para>
    [Parameter]
    public DComSessionOptions? CimDCOMOptions { get; set; }

    /// <para>
    /// Adds specific credentials to the list of known non-working credentials for this computer.
    /// Use this to prevent dbatools from attempting credentials you know will fail, improving performance and avoiding account lockouts.
    /// </para>
    [Parameter]
    public PSCredential[]? AddBadCredential { get; set; }

    /// <para>
    /// Removes previously flagged credentials from the bad credential list for this computer.
    /// Use this when credentials that previously failed have been updated or permissions have been granted.
    /// </para>
    [Parameter]
    public PSCredential[]? RemoveBadCredential { get; set; }

    /// <para>
    /// Removes all entries from the bad credential cache for this computer.
    /// Use this when troubleshooting authentication issues or after bulk credential updates that might affect previously failed credentials.
    /// </para>
    [Parameter]
    public SwitchParameter ClearBadCredential { get; set; }

    /// <para>
    /// Removes any cached working credentials for this computer, forcing fresh authentication on next connection.
    /// Use this when credentials have changed or when you need to ensure the next connection uses newly provided credentials.
    /// </para>
    [Parameter]
    public SwitchParameter ClearCredential { get; set; }

    /// <para>
    /// Performs a complete credential reset by clearing both working and failed credential caches and resetting Windows credential status.
    /// Use this for comprehensive credential troubleshooting or when starting fresh with connection authentication for a host.
    /// </para>
    [Parameter]
    public SwitchParameter ResetCredential { get; set; }

    /// <para>
    /// Clears all connection protocol test results, marking CIM, WMI, and PowerShell remoting as untested for this computer.
    /// Use this to force dbatools to re-test connection methods after network changes, firewall updates, or service configuration changes.
    /// </para>
    [Parameter]
    public SwitchParameter ResetConnectionStatus { get; set; }

    /// <para>
    /// Restores all connection behavior settings to system defaults, removing any computer-specific overrides.
    /// Use this to return a connection to standard behavior after testing custom settings or when troubleshooting connection issues.
    /// </para>
    [Parameter]
    public SwitchParameter ResetConfiguration { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    private bool _disableCache;
    private bool _boundOnCommandLine;
    private bool _seenFirstRecord;
    private DbaCmConnectionParameter[]? _defaultComputerName;

    private static DbaCmConnectionParameter[]? ConvertComputerNameDefault() =>
        (DbaCmConnectionParameter[])LanguagePrimitives.ConvertTo(
            Environment.GetEnvironmentVariable("COMPUTERNAME"),
            typeof(DbaCmConnectionParameter[]), CultureInfo.InvariantCulture);

    protected override void BeginProcessing()
    {
        // Converting the typed default registers a cache entry. An explicit name skips it.
        _boundOnCommandLine = TestBound(nameof(ComputerName));
        _seenFirstRecord = false;
        _defaultComputerName = _boundOnCommandLine ? null : ConvertComputerNameDefault();

        WriteMessage(MessageLevel.InternalComment, "Starting execution");
        WriteMessage(MessageLevel.Verbose, "Bound parameters: " + string.Join(", ", MyInvocation.BoundParameters.Keys));
        _disableCache = LanguagePrimitives.IsTrue(ConfigurationValueLookup.Read("ComputerManagement.Cache.Disable.All", this));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // The function reapplies its typed default between pipeline records.
        if (!_boundOnCommandLine && _seenFirstRecord)
            _defaultComputerName = ConvertComputerNameDefault();
        _seenFirstRecord = true;

        DbaCmConnectionParameter[]? computers = TestBound(nameof(ComputerName)) ? ComputerName : _defaultComputerName;
        foreach (DbaCmConnectionParameter computer in computers ?? Array.Empty<DbaCmConnectionParameter>())
        {
            ManagementConnection? connection = computer?.Success == true ? computer.Connection : null;
            PSObject? snapshot = connection is null ? ManagementConnectionSnapshot.Find(computer?.InputObject) : null;
            string? targetName = connection?.ComputerName ?? ManagementConnectionSnapshot.Name(snapshot);
            if (!ShouldProcess(targetName ?? string.Empty, "Setting Connection"))
                continue;
            if (connection is null && snapshot is not null && targetName is not null)
                connection = ManagementConnectionSnapshot.Restore(snapshot, targetName);
            if (connection is null)
            {
                StopFunction("Failed to interpret computername input: " + LanguagePrimitives.ConvertTo<string>(computer?.InputObject),
                    target: computer?.InputObject, category: ErrorCategory.InvalidArgument, continueLoop: true);
                continue;
            }

            WriteMessage(MessageLevel.VeryVerbose, "Processing computer: " + connection.ComputerName);
            ApplyResets(connection);
            ApplyCredentials(connection);
            ApplySettings(connection);

            if (_disableCache)
                WriteMessage(MessageLevel.Verbose, "Skipping writing to cache, since the cache has been disabled.");
            else
            {
                WriteMessage(MessageLevel.Verbose, "Writing connection to cache");
                ConnectionHost.Connections[connection.ComputerName] = connection;
            }
            WriteObject(connection);
        }
    }

    private void ApplyResets(ManagementConnection connection)
    {
        if (ResetConfiguration)
        {
            WriteMessage(MessageLevel.Verbose, "Resetting the configuration to system default");
            connection.RestoreDefaultConfiguration();
        }
        if (ResetConnectionStatus)
        {
            WriteMessage(MessageLevel.Verbose, "Resetting the connection status");
            connection.CimRM = ManagementConnectionProtocolState.Unknown;
            connection.CimDCOM = ManagementConnectionProtocolState.Unknown;
            connection.Wmi = ManagementConnectionProtocolState.Unknown;
            connection.PowerShellRemoting = ManagementConnectionProtocolState.Unknown;
            connection.LastCimRM = DateTime.MinValue;
            connection.LastCimDCOM = DateTime.MinValue;
            connection.LastWmi = DateTime.MinValue;
            connection.LastPowerShellRemoting = DateTime.MinValue;
        }
        if (ResetCredential)
        {
            WriteMessage(MessageLevel.Verbose, "Resetting credentials");
            connection.KnownBadCredentials.Clear();
            connection.Credentials = null;
            connection.UseWindowsCredentials = false;
            connection.WindowsCredentialsAreBad = false;
        }
        else
        {
            if (ClearBadCredential)
            {
                WriteMessage(MessageLevel.Verbose, "Clearing bad credentials");
                connection.KnownBadCredentials.Clear();
                connection.WindowsCredentialsAreBad = false;
            }
            if (ClearCredential)
            {
                WriteMessage(MessageLevel.Verbose, "Clearing credentials");
                connection.Credentials = null;
                connection.UseWindowsCredentials = false;
            }
        }
    }

    private void ApplyCredentials(ManagementConnection connection)
    {
        foreach (PSCredential credential in RemoveBadCredential ?? Array.Empty<PSCredential>())
            connection.RemoveBadCredential(credential);
        foreach (PSCredential credential in AddBadCredential ?? Array.Empty<PSCredential>())
            connection.AddBadCredential(credential);
        if (TestBound(nameof(Credential)))
            connection.Credentials = Credential;
        if (UseWindowsCredentials)
        {
            connection.Credentials = null;
            connection.UseWindowsCredentials = true;
        }
    }

    private void ApplySettings(ManagementConnection connection)
    {
        if (TestBound(nameof(OverrideExplicitCredential)))
            connection.OverrideExplicitCredential = OverrideExplicitCredential;
        if (TestBound(nameof(DisabledConnectionTypes)))
            connection.DisabledConnectionTypes = DisabledConnectionTypes;
        if (TestBound(nameof(DisableBadCredentialCache)))
            connection.DisableBadCredentialCache = DisableBadCredentialCache;
        if (TestBound(nameof(DisableCimPersistence)))
            connection.DisableCimPersistence = DisableCimPersistence;
        if (TestBound(nameof(DisableCredentialAutoRegister)))
            connection.DisableCredentialAutoRegister = DisableCredentialAutoRegister;
        if (TestBound(nameof(EnableCredentialFailover)))
            connection.EnableCredentialFailover = EnableCredentialFailover;
        if (TestBound(nameof(WindowsCredentialsAreBad)))
            connection.WindowsCredentialsAreBad = WindowsCredentialsAreBad;

        if (TestBound(nameof(CimWinRMOptions)))
            connection.CimWinRMOptions = CimWinRMOptions;
        else if (connection.CimWinRMOptions is null)
            connection.CimWinRMOptions = SetDefaultTimeout(CimOptionDefaults.WinRM());

        if (TestBound(nameof(CimDCOMOptions)))
            connection.CimDComOptions = CimDCOMOptions;
        else if (connection.CimDComOptions is null)
            connection.CimDComOptions = SetDefaultTimeout(CimOptionDefaults.DCom());
        if (TestBound(nameof(OverrideConnectionPolicy)))
            connection.OverrideConnectionPolicy = OverrideConnectionPolicy;
    }

    private T SetDefaultTimeout<T>(T options) where T : CimSessionOptions
    {
        object value = ConfigurationValueLookup.Read("ComputerManagement.CimOperationTimeout", this) ?? TimeSpan.FromSeconds(60);
        try
        {
            // The helper assigns the configuration through the PowerShell adapter which handles type conversion.
            PSObject.AsPSObject(options).Properties[nameof(options.Timeout)].Value = value;
        }
        catch (SetValueException failure)
        {
            // Preserve the setter error record and respect an enclosing try or error preference.
            StatementFault.Surface(this, new ErrorRecord(failure.ErrorRecord, failure));
        }
        return options;
    }

    protected override void EndProcessing()
    {
        if (!Interrupted)
            WriteMessage(MessageLevel.InternalComment, "Stopping execution");
    }
}
