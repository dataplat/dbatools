#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Data.Common;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Builds SQL Server connection strings from PowerShell-friendly parameters. Port of
/// public/New-DbaConnectionString.ps1 (W1-027). Two code paths like the function: the
/// modern default (Microsoft.Data.SqlClient builder, built natively) and the
/// sql.connection.legacy config path (SMO ConnectionContext assembly). The -Legacy
/// System.Data.SqlClient builder is created through nested PS New-Object so type
/// resolution and availability match the engine per edition, then driven through the
/// DbConnectionStringBuilder base indexer (virtual dispatch reaches the typed
/// validation). Under -WhatIf BOTH ShouldProcess sites print per instance, because the
/// function's new-path emit+continue sits inside the first gate and execution falls
/// through to the legacy site - preserved. Positions 0-18 pin the PS implicit
/// positional binding: non-switch parameters number consecutively in declaration order
/// and switches are never positional (gate-pinned). Config defaults ride the REAL Get-DbatoolsConfigValue nested
/// (Mandatory/Optional coercions included). Lab-pinned strings in
/// migration probe-connstring-w1027 (P1-P15) and tests/New-DbaConnectionString.Tests.ps1
/// (TA-034). Surface pinned by migration/baselines/New-DbaConnectionString.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaConnectionString", SupportsShouldProcess = true)]
public sealed class NewDbaConnectionStringCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [Alias("ServerInstance", "SqlServer", "Server", "DataSource")]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    [Parameter(Position = 1)]
    [Alias("SqlCredential")]
    public PSCredential? Credential { get; set; }

    [Parameter(Position = 2)]
    public string? AccessToken { get; set; }

    [Parameter(Position = 3)]
    [PsStringCast]
    [ValidateSet("ReadOnly", "ReadWrite")]
    public string? ApplicationIntent { get; set; }

    [Parameter(Position = 4)]
    public string? BatchSeparator { get; set; }

    [Parameter(Position = 5)]
    public string? ClientName { get; set; } = "custom connection";

    [Parameter(Position = 6)]
    public int ConnectTimeout { get; set; }

    [Parameter(Position = 7)]
    public string? Database { get; set; }

    [Parameter]
    public SwitchParameter EncryptConnection { get; set; }

    [Parameter(Position = 8)]
    public string? FailoverPartner { get; set; }

    [Parameter]
    public SwitchParameter IsActiveDirectoryUniversalAuth { get; set; }

    [Parameter(Position = 9)]
    public int LockTimeout { get; set; }

    [Parameter(Position = 10)]
    public int MaxPoolSize { get; set; }

    [Parameter(Position = 11)]
    public int MinPoolSize { get; set; }

    [Parameter]
    public SwitchParameter MultipleActiveResultSets { get; set; }

    [Parameter]
    public SwitchParameter MultiSubnetFailover { get; set; }

    [Parameter(Position = 12)]
    [PsStringCast]
    [ValidateSet("TcpIp", "NamedPipes", "Multiprotocol", "AppleTalk", "BanyanVines", "Via", "SharedMemory", "NWLinkIpxSpx")]
    public string? NetworkProtocol { get; set; }

    [Parameter]
    public SwitchParameter NonPooledConnection { get; set; }

    [Parameter(Position = 13)]
    public int PacketSize { get; set; }

    [Parameter(Position = 14)]
    public int PooledConnectionLifetime { get; set; }

    [Parameter(Position = 15)]
    [PsStringCast]
    [ValidateSet("CaptureSql", "ExecuteAndCaptureSql", "ExecuteSql")]
    public string? SqlExecutionModes { get; set; }

    [Parameter(Position = 16)]
    public int StatementTimeout { get; set; }

    [Parameter]
    public SwitchParameter TrustServerCertificate { get; set; }

    [Parameter(Position = 17)]
    public string? WorkstationId { get; set; }

    [Parameter]
    public SwitchParameter Legacy { get; set; }

    [Parameter(Position = 18)]
    public string? AppendConnectionString { get; set; }

    protected override void BeginProcessing()
    {
        // PS param defaults: [switch]$EncryptConnection = (Get-DbatoolsConfigValue
        // -FullName 'sql.connection.encrypt') and the TrustServerCertificate analogue run
        // at bind time when not bound.
        if (!TestBound("EncryptConnection"))
            EncryptConnection = new SwitchParameter(LanguagePrimitives.IsTrue(GetConfigValue("sql.connection.encrypt")));
        if (!TestBound("TrustServerCertificate"))
            TrustServerCertificate = new SwitchParameter(LanguagePrimitives.IsTrue(GetConfigValue("sql.connection.trustcert")));
    }

    // PS: $isAzure = $true is the only assignment in the function - FUNCTION scope, never
    // initialized or reset, so once an Azure instance latches it every later instance and
    // pipeline record takes the Azure auth branch too (DEF-008 re-open: a block-local flag
    // built the wrong-auth string only where the source ALSO builds it).
    private bool _isAzure;

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter inputInstance in SqlInstance)
        {
            DbaInstanceParameter instance = inputInstance;

            // The new code path (formerly known as experimental) is now the default.
            // To have a quick way to switch back in case any problems occur, the switch "legacy" is introduced: Set-DbatoolsConfig -FullName sql.connection.legacy -Value $true
            // All the sub paths inside the following if clause will end with a continue, so the normal code path is not used.
            if (!LanguagePrimitives.IsTrue(GetConfigValue("sql.connection.legacy")))
            {
                WriteMessage(MessageLevel.Debug, "We have to build a connect string, using these parameters: " + string.Join(" ", MyInvocation.BoundParameters.Keys));

                // Test for unsupported parameters
                if (TestBound("LockTimeout"))
                    WriteMessage(MessageLevel.Warning, "Parameter LockTimeout not supported, because it is not part of a connection string.");
                // TODO: That can be added to the Data Source - but why?
                //if (Test-Bound -ParameterName 'NetworkProtocol') {
                //    Write-Message -Level Warning -Message "Parameter NetworkProtocol not supported, because it is not part of a connection string."
                //}
                if (TestBound("StatementTimeout"))
                    WriteMessage(MessageLevel.Warning, "Parameter StatementTimeout not supported, because it is not part of a connection string.");
                if (TestBound("SqlExecutionModes"))
                    WriteMessage(MessageLevel.Warning, "Parameter SqlExecutionModes not supported, because it is not part of a connection string.");

                // Set defaults like in Connect-DbaInstance
                if (!TestBound("Database"))
                    Database = LanguagePrimitives.ConvertTo<string>(GetConfigValue("sql.connection.database"));
                if (!TestBound("ClientName"))
                    ClientName = LanguagePrimitives.ConvertTo<string>(GetConfigValue("sql.connection.clientname"));
                if (!TestBound("ConnectTimeout"))
                    ConnectTimeout = ConnectionHost.SqlConnectionTimeout;
                if (!TestBound("NetworkProtocol"))
                {
                    object? np = GetConfigValue("sql.connection.protocol");
                    if (LanguagePrimitives.IsTrue(np))
                        NetworkProtocol = LanguagePrimitives.ConvertTo<string>(np);
                }
                if (!TestBound("PacketSize"))
                    PacketSize = LanguagePrimitives.ConvertTo<int>(GetConfigValue("sql.connection.packetsize"));
                if (!TestBound("TrustServerCertificate"))
                    TrustServerCertificate = new SwitchParameter(LanguagePrimitives.IsTrue(GetConfigValue("sql.connection.trustcert")));
                // TODO: Maybe put this in a config item:
                string azureDomain = "database.windows.net";

                // Rename credential parameter to align with other commands, later rename parameter
                PSCredential? sqlCredential = Credential;

                if (ShouldProcess(PsText(instance), "Making a new Connection String"))
                {
                    string? connstring;
                    if (PsString.Eq(PsText(PsProperty.Get(instance, "Type")), "Server"))
                    {
                        object? existingConnectionString = PsProperty.Get(PsProperty.Get(PsProperty.Get(instance, "InputObject"), "ConnectionContext"), "ConnectionString");
                        WriteMessage(MessageLevel.Debug, "server object passed in, connection string is: " + PsText(existingConnectionString));
                        DbConnectionStringBuilder connStringBuilder;
                        if (Legacy.ToBool())
                        {
                            // PS: $instance.InputObject.ConnectionContext.ConnectionString | Convert-ConnectionString
                            // then New-Object System.Data.SqlClient.SqlConnectionStringBuilder $converted -
                            // both ride nested PS (private helper + engine type resolution).
                            connStringBuilder = BuildLegacyBuilder(existingConnectionString, convertFirst: true);
                        }
                        else
                        {
                            connStringBuilder = new Microsoft.Data.SqlClient.SqlConnectionStringBuilder(PsText(existingConnectionString));
                        }
                        // In Azure, check for a database change
                        if (TestAzure(instance, azureDomain) && LanguagePrimitives.IsTrue(Database))
                            connStringBuilder["Initial Catalog"] = Database;
                        connstring = connStringBuilder.ConnectionString;
                        // TODO: Should we check the other parameters and change the connection string accordingly?
                    }
                    else
                    {
                        DbConnectionStringBuilder connStringBuilder;
                        if (Legacy.ToBool())
                            connStringBuilder = BuildLegacyBuilder(null, convertFirst: false);
                        else
                            connStringBuilder = new Microsoft.Data.SqlClient.SqlConnectionStringBuilder();
                        connStringBuilder["Data Source"] = instance.FullSmoName;
                        if (LanguagePrimitives.IsTrue(ApplicationIntent))
                            connStringBuilder["ApplicationIntent"] = ApplicationIntent;
                        if (LanguagePrimitives.IsTrue(ClientName))
                            connStringBuilder["Application Name"] = ClientName;
                        if (ConnectTimeout != 0)
                            connStringBuilder["Connect Timeout"] = ConnectTimeout;
                        if (LanguagePrimitives.IsTrue(Database))
                            connStringBuilder["Initial Catalog"] = Database;
                        // https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlconnectionstringbuilder.encrypt?view=sqlclient-dotnet-standard-5.0
                        if (!Regex.IsMatch(PsText(instance), "localdb", RegexOptions.IgnoreCase))
                        {
                            if (EncryptConnection.ToBool())
                                connStringBuilder["Encrypt"] = "Mandatory";
                            if (!EncryptConnection.ToBool() && TestBound("EncryptConnection"))
                                connStringBuilder["Encrypt"] = "False";
                        }
                        else
                        {
                            WriteMessage(MessageLevel.Verbose, "localdb detected, skipping unsupported keyword 'Encryption'");
                        }
                        if (LanguagePrimitives.IsTrue(FailoverPartner))
                            connStringBuilder["Failover Partner"] = FailoverPartner;
                        if (MaxPoolSize != 0)
                            connStringBuilder["Max Pool Size"] = MaxPoolSize;
                        if (MinPoolSize != 0)
                            connStringBuilder["Min Pool Size"] = MinPoolSize;
                        if (MultipleActiveResultSets.ToBool())
                            connStringBuilder["MultipleActiveResultSets"] = true;
                        else
                            connStringBuilder["MultipleActiveResultSets"] = false;
                        if (MultiSubnetFailover.ToBool())
                            connStringBuilder["MultiSubnetFailover"] = true;
                        if (NonPooledConnection.ToBool())
                            connStringBuilder["Pooling"] = false;
                        if (PacketSize != 0)
                            connStringBuilder["Packet Size"] = PacketSize;
                        if (PooledConnectionLifetime != 0)
                            connStringBuilder["Load Balance Timeout"] = PooledConnectionLifetime;
                        if (TrustServerCertificate.ToBool())
                            connStringBuilder["TrustServerCertificate"] = true;
                        else
                            connStringBuilder["TrustServerCertificate"] = false;
                        if (LanguagePrimitives.IsTrue(WorkstationId))
                            connStringBuilder["Workstation Id"] = WorkstationId;
                        if (LanguagePrimitives.IsTrue(sqlCredential))
                        {
                            WriteMessage(MessageLevel.Debug, "We have a SqlCredential");
                            string username = sqlCredential!.UserName!.TrimStart('\\');
                            // support both ad\username and username@ad
                            if (username.Contains("\\"))
                            {
                                // PS: $domain, $login = $username.Split("\") - the second
                                // target takes the REST (an array stringifies space-joined).
                                string[] parts = username.Split('\\');
                                string domain = parts[0];
                                string login = parts.Length == 2 ? parts[1] : string.Join(" ", parts, 1, parts.Length - 1);
                                username = login + "@" + domain;
                            }
                            connStringBuilder["User ID"] = username;
                            connStringBuilder["Password"] = sqlCredential.GetNetworkCredential().Password;
                            if (TestAzure(instance, azureDomain) && username.Contains("@"))
                            {
                                WriteMessage(MessageLevel.Debug, "We connect to Azure with Azure AD account, so adding Authentication=Active Directory Password");
                                connStringBuilder["Authentication"] = "Active Directory Password";
                            }
                        }
                        else
                        {
                            WriteMessage(MessageLevel.Debug, "We don't have a SqlCredential");
                            if (TestAzure(instance, azureDomain))
                            {
                                WriteMessage(MessageLevel.Debug, "We connect to Azure, so adding Authentication=Active Directory Integrated");
                                connStringBuilder["Authentication"] = "Active Directory Integrated";
                            }
                            else
                            {
                                WriteMessage(MessageLevel.Debug, "We don't connect to Azure, so setting Integrated Security=True");
                                connStringBuilder["Integrated Security"] = true;
                            }
                        }

                        // special config for Azure
                        if (TestAzure(instance, azureDomain))
                        {
                            if (!TestBound("ConnectTimeout"))
                                connStringBuilder["Connect Timeout"] = 30;
                            connStringBuilder["Encrypt"] = true;
                            // Why adding tcp:?
                            //$connStringBuilder['Data Source'] = "tcp:$($instance.ComputerName),$($instance.Port)"
                        }
                        if (Legacy.ToBool())
                            connstring = connStringBuilder.ConnectionString;
                        else
                            connstring = connStringBuilder.ToString();
                        if (LanguagePrimitives.IsTrue(AppendConnectionString))
                        {
                            // TODO: Check if new connection string is still valid
                            connstring = connstring + ";" + AppendConnectionString;
                        }
                    }
                    WriteObject(connstring);
                    continue;
                }
            }
            // This is the end of the new default code path.
            // All session with the configuration "sql.connection.legacy" set to $true will run through the following code.
            // To use the legacy code path: Set-DbatoolsConfig -FullName sql.connection.legacy -Value $true

            WriteMessage(MessageLevel.Debug, "sql.connection.legacy is used");

            if (ShouldProcess(PsText(instance), "Making a new Connection String"))
            {
                object? inputObject = PsProperty.Get(instance, "InputObject");
                bool azureName = Regex.IsMatch(instance.ComputerName ?? "", "database\\.windows\\.net", RegexOptions.IgnoreCase) ||
                    Regex.IsMatch(PsText(PsProperty.Get(inputObject, "ComputerName")), "database\\.windows\\.net", RegexOptions.IgnoreCase);
                if (azureName)
                {
                    if (inputObject is Server smoInput)
                    {
                        string azureConnstring = PsText(PsProperty.Get(PsProperty.Get(smoInput, "ConnectionContext"), "ConnectionString"));
                        if (LanguagePrimitives.IsTrue(Database))
                        {
                            // PS: $connstring -split ';' | Where-Object { $_.StartsWith("Initial Catalog") }
                            string? olddb = null;
                            foreach (string piece in azureConnstring.Split(';'))
                            {
                                if (piece.StartsWith("Initial Catalog"))
                                {
                                    olddb = piece;
                                    break;
                                }
                            }
                            string newdb = "Initial Catalog=" + Database;
                            if (LanguagePrimitives.IsTrue(olddb))
                                azureConnstring = azureConnstring.Replace(olddb!, newdb);
                            else
                                azureConnstring = azureConnstring + ";" + newdb + ";";
                        }
                        WriteObject(azureConnstring);
                        continue;
                    }
                    else
                    {
                        _isAzure = true;

                        if (!TestBound("ConnectTimeout"))
                            ConnectTimeout = 30;

                        if (!TestBound("ClientName"))
                            ClientName = "dbatools PowerShell module - dbatools.io";
                        EncryptConnection = new SwitchParameter(true);
                        instance = new DbaInstanceParameter("tcp:" + instance.ComputerName + "," + instance.Port);
                    }
                }

                // PS: if ($instance.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server])
                // - dead in PS too: foreach over [DbaInstanceParameter[]] never yields Server.
                Guid guid = Guid.NewGuid();
                Server server = new(guid.ToString());

                if (LanguagePrimitives.IsTrue(AppendConnectionString))
                {
                    string baseConnstring = server.ConnectionContext.ConnectionString;
                    server.ConnectionContext.ConnectionString = baseConnstring + ";" + AppendConnectionString;
                    WriteObject(server.ConnectionContext.ConnectionString);
                }
                else
                {
                    server.ConnectionContext.ApplicationName = ClientName;
                    if (LanguagePrimitives.IsTrue(BatchSeparator))
                        server.ConnectionContext.BatchSeparator = BatchSeparator;
                    if (ConnectTimeout != 0)
                        server.ConnectionContext.ConnectTimeout = ConnectTimeout;
                    if (LanguagePrimitives.IsTrue(Database))
                        server.ConnectionContext.DatabaseName = Database;
                    if (EncryptConnection.ToBool())
                        server.ConnectionContext.EncryptConnection = true;
                    if (IsActiveDirectoryUniversalAuth.ToBool())
                    {
                        // The shipped SMO ServerConnection no longer exposes this property;
                        // the FUNCTION faults at runtime on this line, so the nested PS
                        // property set reproduces whatever the engine does per SMO version.
                        NestedCommand.InvokeScoped(this, SetUniversalAuthScript, server.ConnectionContext);
                    }
                    if (LockTimeout != 0)
                        server.ConnectionContext.LockTimeout = LockTimeout;
                    if (MaxPoolSize != 0)
                        server.ConnectionContext.MaxPoolSize = MaxPoolSize;
                    if (MinPoolSize != 0)
                        server.ConnectionContext.MinPoolSize = MinPoolSize;
                    if (MultipleActiveResultSets.ToBool())
                        server.ConnectionContext.MultipleActiveResultSets = true;
                    if (LanguagePrimitives.IsTrue(NetworkProtocol))
                        server.ConnectionContext.NetworkProtocol = (Microsoft.SqlServer.Management.Common.NetworkProtocol)Enum.Parse(typeof(Microsoft.SqlServer.Management.Common.NetworkProtocol), NetworkProtocol!, true);
                    if (NonPooledConnection.ToBool())
                        server.ConnectionContext.NonPooledConnection = true;
                    if (PacketSize != 0)
                        server.ConnectionContext.PacketSize = PacketSize;
                    if (PooledConnectionLifetime != 0)
                        server.ConnectionContext.PooledConnectionLifetime = PooledConnectionLifetime;
                    if (StatementTimeout != 0)
                        server.ConnectionContext.StatementTimeout = StatementTimeout;
                    if (LanguagePrimitives.IsTrue(SqlExecutionModes))
                        server.ConnectionContext.SqlExecutionModes = (Microsoft.SqlServer.Management.Common.SqlExecutionModes)Enum.Parse(typeof(Microsoft.SqlServer.Management.Common.SqlExecutionModes), SqlExecutionModes!, true);
                    if (TrustServerCertificate.ToBool())
                        server.ConnectionContext.TrustServerCertificate = true;
                    if (LanguagePrimitives.IsTrue(WorkstationId))
                        server.ConnectionContext.WorkstationId = WorkstationId;

                    if (Credential is not null && Credential.UserName is not null)
                    {
                        string username = Credential.UserName.TrimStart('\\');

                        if (username.Contains("\\"))
                        {
                            username = username.Split('\\')[1];
                            server.ConnectionContext.LoginSecure = true;
                            server.ConnectionContext.ConnectAsUser = true;
                            server.ConnectionContext.ConnectAsUserName = username;
                            server.ConnectionContext.ConnectAsUserPassword = Credential.GetNetworkCredential().Password;
                        }
                        else
                        {
                            server.ConnectionContext.LoginSecure = false;
                            server.ConnectionContext.Login = username;
                            server.ConnectionContext.SecurePassword = Credential.Password;
                        }
                    }

                    string connstring = server.ConnectionContext.ConnectionString;
                    if (MultiSubnetFailover.ToBool())
                        connstring = connstring + ";MultiSubnetFailover=True";
                    if (LanguagePrimitives.IsTrue(FailoverPartner))
                        connstring = connstring + ";Failover Partner=" + FailoverPartner;
                    if (LanguagePrimitives.IsTrue(ApplicationIntent))
                        connstring = connstring + ";ApplicationIntent=" + ApplicationIntent + ";";

                    if (_isAzure)
                    {
                        if (LanguagePrimitives.IsTrue(Credential))
                        {
                            if (Credential!.UserName!.Contains("\\") || Credential.UserName.Contains("@"))
                            {
                                connstring = connstring + ";Authentication=\"Active Directory Password\"";
                            }
                            else
                            {
                                string username = Credential.UserName.TrimStart('\\');
                                server.ConnectionContext.LoginSecure = false;
                                server.ConnectionContext.Login = username;
                                server.ConnectionContext.SecurePassword = Credential.Password;
                            }
                        }
                        else
                        {
                            connstring = connstring.Replace("Integrated Security=True;", "Persist Security Info=True;");
                            if (!LanguagePrimitives.IsTrue(AccessToken))
                                connstring = connstring + ";Authentication=\"Active Directory Integrated\"";
                        }
                    }

                    if (!PsString.Eq(connstring, server.ConnectionContext.ConnectionString))
                        server.ConnectionContext.ConnectionString = connstring;

                    WriteObject(server.ConnectionContext.ConnectionString.Replace(guid.ToString(), PsText(instance)));
                }
            }
        }
    }

    /// <summary>
    /// The begin-block Test-Azure helper: matches the instance ComputerName against the
    /// azure domain REGEX (dots match any character, like the PS -match).
    /// </summary>
    private bool TestAzure(DbaInstanceParameter instance, string azureDomain)
    {
        if (Regex.IsMatch(instance.ComputerName ?? "", azureDomain, RegexOptions.IgnoreCase))
        {
            WriteMessage(MessageLevel.Debug, "Test for Azure is positive");
            return true;
        }
        WriteMessage(MessageLevel.Debug, "Test for Azure is negative");
        return false;
    }

    /// <summary>
    /// Creates the -Legacy System.Data.SqlClient.SqlConnectionStringBuilder through nested
    /// PS (engine type resolution per edition), optionally piping the source string through
    /// the private Convert-ConnectionString first, exactly like the function.
    /// </summary>
    private DbConnectionStringBuilder BuildLegacyBuilder(object? sourceConnectionString, bool convertFirst)
    {
        Collection<PSObject> output;
        if (convertFirst)
            output = NestedCommand.InvokeScoped(this, LegacyBuilderFromStringScript, sourceConnectionString);
        else
            output = NestedCommand.InvokeScoped(this, LegacyBuilderEmptyScript);
        if (output.Count > 0 && output[0]?.BaseObject is DbConnectionStringBuilder builder)
            return builder;
        throw new InvalidOperationException("System.Data.SqlClient.SqlConnectionStringBuilder could not be created.");
    }

    /// <summary>PS: $x = (Get-DbatoolsConfigValue -FullName ...) via the real command.</summary>
    private object? GetConfigValue(string fullName)
    {
        Hashtable splatValue = new();
        splatValue["FullName"] = fullName;
        Collection<PSObject> output = NestedCommand.Invoke(this, "Get-DbatoolsConfigValue", splatValue);
        if (output.Count == 0)
            return null;
        return output[0]?.BaseObject;
    }

    /// <summary>PS string interpolation of a value.</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }


    private const string SetUniversalAuthScript = """
param($connectionContext)
$connectionContext.IsActiveDirectoryUniversalAuth = $true
""";

    private const string LegacyBuilderFromStringScript = """
param($connectionString)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($connectionString)
    $converted = $connectionString | Convert-ConnectionString
    New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $converted
} $connectionString
""";

    private const string LegacyBuilderEmptyScript = """
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder
}
""";
}
