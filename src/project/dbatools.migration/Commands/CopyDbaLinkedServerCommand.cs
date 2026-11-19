#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using System.Security.Principal;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Copy-DbaLinkedServer.ps1; the passwords come from LinkedServerLoginSecrets, the native
// Get-DecryptedObject -Type LinkedServer.
/// <summary>Migrates linked servers and their authentication credentials from one SQL Server instance to another</summary>
[Cmdlet(VerbsCommon.Copy, "DbaLinkedServer", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaLinkedServerCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance. Requires sysadmin on both SQL Server and Windows.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Windows credential used to reach the source OS when passwords are decrypted.</summary>
    [Parameter(Position = 4)]
    public PSCredential? Credential { get; set; }

    /// <summary>Only copy the linked servers with these names.</summary>
    [Parameter(Position = 5)]
    public object[]? LinkedServer { get; set; }

    /// <summary>Skip the linked servers with these names.</summary>
    [Parameter(Position = 6)]
    public object[]? ExcludeLinkedServer { get; set; }

    /// <summary>Rewrite SQLNCLI providers to the newest one present on the destination.</summary>
    [Parameter]
    public SwitchParameter UpgradeSqlClient { get; set; }

    /// <summary>Copy linked server definitions without decrypting and carrying over the passwords.</summary>
    [Parameter]
    public SwitchParameter ExcludePassword { get; set; }

    /// <summary>Drop and recreate linked servers that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // No parameter takes pipeline input, so begin, process and end run once each; one ProcessRecord keeps the
    // source connection in a local and closes an opened DAC in finally.
    protected override void ProcessRecord()
    {
        if (Environment.OSVersion.Platform != PlatformID.Win32NT)
        {
            StopFunction("Copy-DbaLinkedServer is only supported on Windows");
            return;
        }

        // PS: $null = Test-ElevationRequirement -ComputerName $Source.ComputerName - its Stop-Function interrupts the
        // command but begin still runs to its end.
        if (!ElevationSatisfied())
            StopFunction("Console not elevated, but elevation is required to perform some actions on localhost for this command.");

        if (SourceSqlCredential?.UserName is not null)
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                "You are using a SQL Credential. Note that this script requires Windows Administrator access on the source server. Attempting with {0}.",
                SourceSqlCredential.UserName));

        Server? sourceServer = null;
        bool dacOpened = false;
        try
        {
            try
            {
                if (!ExcludePassword)
                {
                    if (IsDedicatedAdminConnection(Source))
                    {
                        WriteMessage(MessageLevel.Verbose, "Reusing dedicated admin connection for password retrieval.");
                        sourceServer = (Server)Source.InputObject;
                    }
                    else
                    {
                        WriteMessage(MessageLevel.Verbose, "Opening dedicated admin connection for password retrieval.");
                        sourceServer = ConnectServer(Source, SourceSqlCredential, true);
                        dacOpened = true;
                    }
                }
                else
                {
                    WriteMessage(MessageLevel.Verbose, "Opening or reusing normal connection because passwords are excluded.");
                    sourceServer = ConnectServer(Source, SourceSqlCredential, false);
                }
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                StopFunction("Failure", target: Source, errorRecord: new ErrorRecord(ex, "dbatools_Copy-DbaLinkedServer", ErrorCategory.ConnectionError, Source),
                    category: ErrorCategory.ConnectionError);
                return;
            }

            // PS process: if (Test-FunctionInterrupt) { return }
            if (Interrupted)
                return;

            foreach (DbaInstanceParameter destination in Destination)
            {
                CancellationToken.ThrowIfCancellationRequested();
                Server destinationServer;
                try
                {
                    destinationServer = ConnectServer(destination, DestinationSqlCredential, false);
                }
                catch (Exception ex) when (ex is not PipelineStoppedException)
                {
                    StopFunction("Failure", target: destination, errorRecord: new ErrorRecord(ex, "dbatools_Copy-DbaLinkedServer", ErrorCategory.ConnectionError, destination),
                        category: ErrorCategory.ConnectionError, continueLoop: true);
                    continue;
                }
                if (!IsSysadmin(destinationServer))
                {
                    StopFunction(String.Format(CultureInfo.InvariantCulture, "Not a sysadmin on {0}", destination), target: destinationServer, continueLoop: true);
                    continue;
                }

                // Magic happens here
                CopyLinkedServers(sourceServer, destinationServer, destination);
            }
        }
        finally
        {
            if (dacOpened && sourceServer is not null)
                sourceServer.ConnectionContext.Disconnect();
            SetActiveConnection(null!);
        }
    }

    /// <summary>The pinned inner function Copy-DbaLinkedServers, run once per destination.</summary>
    private void CopyLinkedServers(Server sourceServer, Server destinationServer, DbaInstanceParameter destination)
    {
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
            "Collecting Linked Server logins and passwords on {0}.", sourceServer.Name));
        // With -ExcludePassword the pin builds its login list from an unset variable, so no name matches and no
        // login is processed; without a list the same holds.
        LinkedServerLoginSecrets? secrets = ExcludePassword ? null : ReadSecrets(sourceServer);
        try
        {
            List<LinkedServer> serverList = sourceServer.LinkedServers.Cast<LinkedServer>().ToList();
            // The inner function types its -LinkedServer as [string[]]; -ExcludeLinkedServer stays [object[]].
            string[]? names = LinkedServer is null ? null : (string[])LanguagePrimitives.ConvertTo(LinkedServer, typeof(string[]), CultureInfo.InvariantCulture);
            if (LanguagePrimitives.IsTrue(names))
                serverList = serverList.Where(server => InList(server.Name, names)).ToList();
            if (LanguagePrimitives.IsTrue(ExcludeLinkedServer))
                serverList = serverList.Where(server => !InList(server.Name, ExcludeLinkedServer)).ToList();

            foreach (LinkedServer current in serverList)
            {
                CancellationToken.ThrowIfCancellationRequested();
                CopyLinkedServer(sourceServer, destinationServer, destination, current, secrets);
            }
        }
        finally
        {
            secrets?.Dispose();
        }
    }

    /// <summary>One pass of the pinned foreach over the linked servers; every return is the pin's continue.</summary>
    private void CopyLinkedServer(Server sourceServer, Server destinationServer, DbaInstanceParameter destination,
        LinkedServer current, LinkedServerLoginSecrets? secrets)
    {
        string? provider = current.ProviderName;
        try
        {
            destinationServer.LinkedServers.Refresh();
            foreach (LinkedServer existingServer in destinationServer.LinkedServers)
                existingServer.LinkedServerLogins.Refresh();
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            // The pin ignores refresh failures ("here to avoid an empty catch").
            WriteMessage(MessageLevel.Debug, ex.Message);
        }

        string name = current.Name;
        StatusRow row = new(SmoServerExtensions.GetDomainInstanceName(sourceServer), SmoServerExtensions.GetDomainInstanceName(destinationServer),
            name, current.ProductName, current.DataSource, provider);

        // This does a check to warn of missing OleDbProviderSettings but should only be checked on SQL on Windows
        List<string> providerNames = destinationServer.Settings.OleDbProviderSettings.Cast<OleDbProviderSettings>().Select(setting => setting.Name).ToList();
        if (providerNames.Count > 1 || (providerNames.Count == 1 && !String.IsNullOrEmpty(providerNames[0])))
        {
            if (destinationServer.VersionMajor >= 17 && LanguagePrimitives.Equals(provider, "MSOLEDBSQL", true, CultureInfo.InvariantCulture))
            {
                WriteMessage(MessageLevel.Verbose, "Upgrading provider from MSOLEDBSQL to MSOLEDBSQL19 to ensure compatibility with SQL Server 2025+.");
                provider = "MSOLEDBSQL19";
            }
            if (!providerNames.Any(providerName => LanguagePrimitives.Equals(providerName, provider, true, CultureInfo.InvariantCulture)) &&
                provider is not null && !provider.StartsWith("SQLN", StringComparison.Ordinal))
            {
                string missing = String.Format(CultureInfo.InvariantCulture, "{0} does not support the {1} provider. Skipping {2}.",
                    destinationServer.Name, provider, name);
                if (Approve(destination, missing))
                {
                    row.Status = "Skipped";
                    row.Notes = "Missing provider";
                    Emit(row);
                    WriteMessage(MessageLevel.Verbose, missing);
                }
                return;
            }
        }

        if (destinationServer.LinkedServers[name] is not null)
        {
            if (!Force)
            {
                if (Approve(destination, String.Format(CultureInfo.InvariantCulture, "Linked server {0} exists on {1}", name, destinationServer.Name)))
                {
                    row.Status = "Skipped";
                    row.Notes = "Already exists on destination";
                    Emit(row);
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Linked server {0} exists on {1}.", name, destinationServer.Name));
                }
                return;
            }
            if (Approve(destination, "Dropping " + name))
            {
                if (LanguagePrimitives.Equals(name, "repl_distributor", true, CultureInfo.InvariantCulture))
                {
                    WriteMessage(MessageLevel.Verbose, "repl_distributor cannot be dropped. Not going to try.");
                    return;
                }
                ErrorRecord? dropFault = null;
                try
                {
                    destinationServer.LinkedServers[name].Drop(true);
                }
                catch (Exception ex) when (ex is not PipelineStoppedException)
                {
                    dropFault = MethodRecord(ex, "Drop", 1);
                }
                if (dropFault is null)
                {
                    try { destinationServer.LinkedServers.Refresh(); }
                    catch (Exception ex) when (ex is not PipelineStoppedException) { dropFault = MethodRecord(ex, "Refresh", 0); }
                }
                if (dropFault is not null)
                {
                    string issue = String.Format(CultureInfo.InvariantCulture, "Issue dropping linked server {0} on {1} | {2}", name, destination, dropFault);
                    row.Status = "Failed";
                    row.Notes = issue;
                    Emit(row);
                    WriteMessage(MessageLevel.Verbose, issue);
                    return;
                }
            }
        }

        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Attempting to migrate: {0}.", name));
        if (Approve(destination, "Migrating " + name))
        {
            ErrorRecord? createFault = CreateLinkedServer(destinationServer, current, row, provider);
            if (createFault is not null)
            {
                row.Notes = MessageService.GetErrorMessage(createFault);
                row.Status = "Failed";
                Emit(row);
                WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Issue creating linked server {0} on {1} | {2}", name, destination, createFault));
                return;
            }
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "{0} successfully copied.", name));
            row.Status = "Successful";
            Emit(row);
        }

        if (secrets is null)
            return;
        LinkedServerLoginCollection? destinationLogins = destinationServer.LinkedServers[name]?.LinkedServerLogins;
        foreach (LinkedServerLoginSecret login in secrets.Logins.Where(secret => LanguagePrimitives.Equals(secret.Name, name, true, CultureInfo.InvariantCulture)))
        {
            // Correction remote-login-identity: the pin's case-insensitive RemoteUser -eq also matched other mappings
            // (App and app, or one remote user under two local logins) and gave them this password; match the mapping
            // itself, its local login and its exact remote user.
            List<LinkedServerLogin> matches = destinationLogins is null ? new List<LinkedServerLogin>() :
                destinationLogins.Cast<LinkedServerLogin>().Where(candidate =>
                    String.Equals(candidate.RemoteUser, login.Identity, StringComparison.Ordinal) &&
                    LanguagePrimitives.Equals(candidate.Name ?? "", login.LocalLogin ?? "", true, CultureInfo.InvariantCulture)).ToList();
            row.Type = login.Identity;
            // PS: $currentlogin.RemoteUser.length -ne 0 - the string length for one match, the count for several.
            if (matches.Count > 1 || (matches.Count == 1 && !String.IsNullOrEmpty(matches[0].RemoteUser)))
                CopyLoginPassword(destination, row, login, matches);
        }
    }

    /// <summary>The pin's create try block; returns the record its catch would receive, or null on success.</summary>
    private ErrorRecord? CreateLinkedServer(Server destinationServer, LinkedServer current, StatusRow row, string? provider)
    {
        StringBuilder script = new();
        try
        {
            // PS: $currentLinkedServer.Script() | Out-String
            foreach (string? line in current.Script())
                script.AppendLine(line);
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            return MethodRecord(ex, "Script", 0);
        }
        string sql = script.ToString();
        WriteMessage(MessageLevel.Debug, sql);

        if (UpgradeSqlClient && Regex.IsMatch(sql, "sqlncli", RegexOptions.IgnoreCase))
        {
            string? newProvider = destinationServer.Settings.OleDbProviderSettings.Cast<OleDbProviderSettings>()
                .Select(setting => setting.Name)
                .Where(providerName => providerName is not null && providerName.StartsWith("SQLNCLI", StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(providerName => providerName, StringComparer.CurrentCultureIgnoreCase)
                .FirstOrDefault();
            WriteMessage(MessageLevel.Verbose, "Changing sqlncli to " + newProvider);
            sql = Regex.Replace(sql, "sqlncli[0-9]+", newProvider ?? "", RegexOptions.IgnoreCase);
        }

        if (LanguagePrimitives.Equals(provider, "MSOLEDBSQL19", true, CultureInfo.InvariantCulture))
        {
            // Starting with SQL Server 2025 (17.x), MSOLEDBSQL uses Microsoft OLE DB Driver version 19, which adds support for TDS 8.0. However, this driver introduces a breaking change. You must now specify the encrypt parameter.
            string? providerString = current.ProviderString;
            if (!String.IsNullOrEmpty(providerString))
            {
                if (!Regex.IsMatch(providerString, @"Encrypt\s*=\s*Optional", RegexOptions.IgnoreCase) &&
                    !Regex.IsMatch(providerString, @"TrustServerCertificate\s*=\s*Yes", RegexOptions.IgnoreCase))
                    WriteMessage(MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture,
                        "Provider string currently set to '{0}', so will not change it. Please verify that it includes 'Encrypt=Optional;TrustServerCertificate=Yes' to ensure connectivity.", providerString));
                else
                    WriteMessage(MessageLevel.Verbose, "Provider string already includes encrypt and trustservercertificate settings, so not modifying it.");
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, "Provider string is empty. Adding 'Encrypt=Optional;TrustServerCertificate=Yes' to provider string for MSOLEDBSQL19.");
                sql = Regex.Replace(sql, "@provider=N'MSOLEDBSQL'", "@provider=N'MSOLEDBSQL19', @provstr=N'Encrypt=Optional;TrustServerCertificate=Yes'", RegexOptions.IgnoreCase);
            }
        }

        try
        {
            // PS: $null = $destServer.Query($sql)
            destinationServer.ConnectionContext.ExecuteWithResults(sql);
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            return QueryRecord(ex);
        }

        if (LanguagePrimitives.Equals(row.ProductName, "SQL Server", true, CultureInfo.InvariantCulture) &&
            !LanguagePrimitives.Equals(row.Name, row.DataSource, true, CultureInfo.InvariantCulture))
        {
            // Correction setnetname-literals: both server-supplied values stay data inside N'' literals.
            string netName = String.Format(CultureInfo.InvariantCulture, "EXEC sp_setnetname N'{0}', N'{1}'; ",
                row.Name.Replace("'", "''"), (row.DataSource ?? "").Replace("'", "''"));
            try
            {
                destinationServer.ConnectionContext.ExecuteWithResults(netName);
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                return QueryRecord(ex);
            }
        }

        try
        {
            destinationServer.LinkedServers.Refresh();
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            return MethodRecord(ex, "Refresh", 0);
        }
        return null;
    }

    /// <summary>The pin's identity block for one source login and its matching destination logins.</summary>
    private void CopyLoginPassword(DbaInstanceParameter destination, StatusRow row, LinkedServerLoginSecret login, List<LinkedServerLogin> matches)
    {
        if (!Approve(destination, "Migrating linked server identity " + login.Identity))
            return;
        ErrorRecord? fault = null;
        if (login.Password is not null && login.Password.Length > 0)
        {
            // Method calls on several matches run on each element, the way PowerShell member enumeration does.
            try
            {
                foreach (LinkedServerLogin match in matches)
                    match.SetRemotePassword(login.Password);
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                fault = MethodRecord(ex, "SetRemotePassword", 1);
            }
            if (fault is null)
            {
                try
                {
                    foreach (LinkedServerLogin match in matches)
                        match.Alter();
                }
                catch (Exception ex) when (ex is not PipelineStoppedException)
                {
                    fault = MethodRecord(ex, "Alter", 0);
                }
            }
        }
        if (fault is null)
        {
            row.Status = "Successful";
            Emit(row);
            return;
        }
        row.Status = "Failed";
        row.Notes = MessageService.GetErrorMessage(fault);
        Emit(row);
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
            "Issue creating linked server identity for {0} on {1} | {2}", login.Identity, destination, fault));
    }

    /// <summary>
    /// PS: Get-DecryptedObject -Type LinkedServer -EnableException:$EnableException. Its Stop-Function runs in the
    /// helper's scope, so without EnableException it warns and the copy continues without passwords.
    /// </summary>
    private LinkedServerLoginSecrets? ReadSecrets(Server sourceServer)
    {
        string sourceName = SmoServerExtensions.GetDomainInstanceName(sourceServer);
        try
        {
            return LinkedServerLoginSecrets.Read(sourceServer, Credential!, CancellationToken,
                message => WriteAttributedMessage("Get-DecryptedObject", MessageLevel.Verbose, message));
        }
        catch (SecretReadException ex)
        {
            string registry = String.Format(CultureInfo.InvariantCulture,
                "Do you have administrative access to the Windows registry on {0}? Otherwise, we're out of ideas.", sourceName);
            switch (ex.Stage)
            {
                case SecretReadStage.ServiceKeyQuery:
                    StopFunction("Can't execute query on " + sourceName, target: sourceServer, errorRecord: QueryRecord(ex.InnerException!), interruptCallerScope: false);
                    break;
                case SecretReadStage.SecretQuery:
                    StopFunction(String.Format(CultureInfo.InvariantCulture, "Can't execute password query on {0}.", sourceName), target: sourceServer,
                        errorRecord: QueryRecord(ex.InnerException!), interruptCallerScope: false);
                    break;
                case SecretReadStage.KeySize:
                    StopFunction("Unknown key size. " + registry, target: sourceName, interruptCallerScope: false);
                    break;
                default:
                    StopFunction(String.Format(CultureInfo.InvariantCulture, "Can't unprotect registry data on {0}. ", sourceName) + registry,
                        target: sourceName, interruptCallerScope: false);
                    break;
            }
            return null;
        }
    }

    private Server ConnectServer(DbaInstanceParameter instance, PSCredential? credential, bool dedicatedAdminConnection)
    {
        SmoConnectionRequest request = new()
        {
            Instance = instance,
            SqlCredential = credential,
            DedicatedAdminConnection = dedicatedAdminConnection,
            // Correction azure-destination-refusal: linked servers aren't available in Azure SQL Database.
            AzureUnsupported = true,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "AzureUnsupported" },
            // The DAC connect runs with -WarningAction SilentlyContinue.
            MessageCallback = (level, message) =>
            {
                if (!dedicatedAdminConnection || level != MessageLevel.Warning)
                    WriteAttributedMessage("Connect-DbaInstance", level, message);
            }
        };
        if (dedicatedAdminConnection)
            request.BoundParameters.Add("DedicatedAdminConnection");
        Server server = ConnectionService.GetServer(request);
        SetActiveConnection(server.ConnectionContext);
        return server;
    }

    /// <summary>PS private Test-DacConnection: a connected Server whose name or connection names ADMIN:.</summary>
    private static bool IsDedicatedAdminConnection(DbaInstanceParameter instance)
    {
        if (instance.Type != DbaInstanceInputType.Server || instance.InputObject is not Server server)
            return false;
        return Regex.IsMatch(server.Name ?? "", "^ADMIN:", RegexOptions.IgnoreCase) ||
            Regex.IsMatch(server.ConnectionContext.ServerInstance ?? "", "^ADMIN:", RegexOptions.IgnoreCase);
    }

    /// <summary>PS private Test-ElevationRequirement: only a localhost source in a non-elevated session fails.</summary>
    private bool ElevationSatisfied()
    {
        if (ConfigurationHost.Configurations.TryGetValue("commands.test-elevationrequirement.disable", out Config? config) &&
            config is not null && LanguagePrimitives.IsTrue(config.Value))
            return true;
        if (!Source.IsLocalHost)
            return true;
        // Unreachable off Windows (ProcessRecord stops first); the guard is the platform check the analyzer reads.
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            return true;
        using WindowsIdentity identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }

    /// <summary>PS private Test-SqlSa on a Server: FixedServerRoles -match "SysAdmin"; any failure is $false.</summary>
    private static bool IsSysadmin(Server server)
    {
        try
        {
            return Regex.IsMatch(server.ConnectionContext.FixedServerRoles.ToString(), "SysAdmin", RegexOptions.IgnoreCase);
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            return false;
        }
    }

    /// <summary>PS: Name -In $list, case-insensitive.</summary>
    private static bool InList(string name, IEnumerable<object?>? list)
    {
        return list is not null && list.Any(value => LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture));
    }

    /// <summary>PS begin: if ($Force) { $ConfirmPreference = 'none' }, so -Force never prompts.</summary>
    private bool Approve(DbaInstanceParameter target, string action)
    {
        if (!Force)
            return ShouldProcess(target.ToString(), action);
        object? saved = SessionState.PSVariable.GetValue("ConfirmPreference");
        SessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
        try { return ShouldProcess(target.ToString(), action); }
        finally { SessionState.PSVariable.Set("ConfirmPreference", saved); }
    }

    /// <summary>The pin's $copyLinkedServer object and its Select-DefaultView output.</summary>
    private sealed class StatusRow
    {
        public StatusRow(string sourceServer, string destinationServer, string name, string? productName, string? dataSource, string? provider)
        {
            SourceServer = sourceServer;
            DestinationServer = destinationServer;
            Name = name;
            ProductName = productName;
            DataSource = dataSource;
            Notes = provider;
            DateTime = new DbaDateTime(System.DateTime.Now);
        }

        public string SourceServer { get; }
        public string DestinationServer { get; }
        public string Name { get; }
        public string? ProductName { get; }
        public string? DataSource { get; }
        public string? Type { get; set; } = "Linked Server";
        public string? Status { get; set; }
        public string? Notes { get; set; }
        public DbaDateTime DateTime { get; }
    }

    private void Emit(StatusRow row)
    {
        // Correction separate-status-rows: each row is its own object holding the values current when it is written.
        PSObject output = new();
        output.Properties.Add(new PSNoteProperty("SourceServer", row.SourceServer));
        output.Properties.Add(new PSNoteProperty("DestinationServer", row.DestinationServer));
        output.Properties.Add(new PSNoteProperty("Name", row.Name));
        output.Properties.Add(new PSNoteProperty("ProductName", row.ProductName));
        output.Properties.Add(new PSNoteProperty("DataSource", row.DataSource));
        output.Properties.Add(new PSNoteProperty("Type", row.Type));
        output.Properties.Add(new PSNoteProperty("Status", row.Status));
        output.Properties.Add(new PSNoteProperty("Notes", row.Notes));
        output.Properties.Add(new PSNoteProperty("DateTime", row.DateTime));
        OutputHelper.SetDefaultDisplayPropertySet(output, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        OutputHelper.InsertTypeName(output, "MigrationObject");
        WriteObject(output);
    }

    /// <summary>The record a script catch receives for a failed .NET method call.</summary>
    private static ErrorRecord MethodRecord(Exception failure, string method, int argumentCount)
    {
        string text = String.Format(CultureInfo.InvariantCulture, "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, argumentCount, failure.Message);
        return new ErrorRecord(new MethodInvocationException(text, failure), failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    /// <summary>
    /// The record a failed dbatools Server.Query raises: its catch joins the messages of the failure's exception
    /// chain and throws that text, which surfaces as 'Exception calling "Query" with "1" argument(s)'.
    /// </summary>
    private static ErrorRecord QueryRecord(Exception failure)
    {
        StringBuilder text = new();
        for (Exception? link = failure; link is not null; link = link.InnerException)
            text.Append(link.Message);
        string joined = text.ToString();
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", joined), new RuntimeException(joined));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
