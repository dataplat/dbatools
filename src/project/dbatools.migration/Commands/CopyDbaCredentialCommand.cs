#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoCredential = Microsoft.SqlServer.Management.Smo.Credential;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Migrates SQL Server credentials between instances while preserving encrypted passwords.
/// </summary>
[Cmdlet(VerbsCommon.Copy, "DbaCredential",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaCredentialCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance. Requires sysadmin and a DAC unless passwords are excluded.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Windows credential used to reach the source OS when passwords are decrypted.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>Destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 4)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy credentials with these names.</summary>
    [Parameter(Position = 5)]
    public string[]? Name { get; set; }

    /// <summary>Skip credentials with these names.</summary>
    [Parameter(Position = 6)]
    public string[]? ExcludeName { get; set; }

    /// <summary>Only copy credentials whose identity matches.</summary>
    [Parameter(Position = 7)]
    [Alias("CredentialIdentity")]
    public string[]? Identity { get; set; }

    /// <summary>Skip credentials whose identity matches.</summary>
    [Parameter(Position = 8)]
    [Alias("ExcludeCredentialIdentity")]
    public string[]? ExcludeIdentity { get; set; }

    /// <summary>Copy credential definitions without decrypting and carrying over the passwords.</summary>
    [Parameter]
    public SwitchParameter ExcludePassword { get; set; }

    /// <summary>Drop and recreate credentials that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Environment.OSVersion.Platform != PlatformID.Win32NT)
        {
            StopFunction("Copy-DbaCredential is only supported on Windows");
            return;
        }

        Server? sourceServer = null;
        SqlCredentialSecrets? secrets = null;
        bool dacOpened = false;
        try
        {
            try
            {
                if (!ExcludePassword && Source.InputObject is Server input &&
                    (input.Name.StartsWith("ADMIN:", StringComparison.OrdinalIgnoreCase) ||
                     input.ConnectionContext.ServerInstance.StartsWith("ADMIN:", StringComparison.OrdinalIgnoreCase)))
                {
                    WriteMessage(MessageLevel.Verbose, "Reusing dedicated admin connection for password retrieval.");
                    sourceServer = input;
                }
                else
                {
                    WriteMessage(MessageLevel.Verbose, ExcludePassword
                        ? "Opening or reusing normal connection because passwords are excluded."
                        : "Opening dedicated admin connection for password retrieval.");
                    sourceServer = ConnectServer(Source, SourceSqlCredential, !ExcludePassword);
                    dacOpened = !ExcludePassword;
                }
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                StopFunction("Failure", target: Source, exception: ex, category: ErrorCategory.ConnectionError);
                return;
            }

            if (!ExcludePassword)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Decrypting all Credential logins and passwords on {0}", sourceServer.Name));
                try
                {
                    secrets = SqlCredentialSecrets.Read(sourceServer, Credential!, CancellationToken,
                        message => WriteAttributedMessage("Get-DecryptedObject", MessageLevel.Verbose, message));
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failed to decrypt credentials on {0}", sourceServer.Name), exception: ex);
                    return;
                }
            }

            WriteMessage(MessageLevel.Verbose, String.Format("Getting all Credentials that should be processed on {0}", sourceServer.Name));
            List<SmoCredential> credentials = sourceServer.Credentials.Cast<SmoCredential>().Where(credential =>
                (!LanguagePrimitives.IsTrue(Name) || Name!.Any(name => LanguagePrimitives.Equals(name, credential.Name, true, CultureInfo.InvariantCulture))) &&
                (!LanguagePrimitives.IsTrue(ExcludeName) || !ExcludeName!.Any(name => LanguagePrimitives.Equals(name, credential.Name, true, CultureInfo.InvariantCulture))) &&
                (!LanguagePrimitives.IsTrue(Identity) || Identity!.Any(identity => LanguagePrimitives.Equals(identity, credential.Identity, true, CultureInfo.InvariantCulture))) &&
                (!LanguagePrimitives.IsTrue(ExcludeIdentity) || !ExcludeIdentity!.Any(identity => LanguagePrimitives.Equals(identity, credential.Identity, true, CultureInfo.InvariantCulture)))).ToList();

            foreach (DbaInstanceParameter destination in Destination)
            {
                CancellationToken.ThrowIfCancellationRequested();
                Server destinationServer;
                try
                {
                    destinationServer = ConnectServer(destination, DestinationSqlCredential, false);
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    StopFunction("Failure", target: destination, exception: ex,
                        category: ErrorCategory.ConnectionError, continueLoop: true);
                    continue;
                }
                WriteMessage(MessageLevel.Verbose, "Starting migration");
                destinationServer.Credentials.Refresh();
                foreach (SmoCredential credential in credentials)
                {
                    CancellationToken.ThrowIfCancellationRequested();
                    CopyCredential(sourceServer, destinationServer, destination, credential, secrets);
                }
            }
        }
        finally
        {
            secrets?.Dispose();
            if (dacOpened && sourceServer is not null)
                sourceServer.ConnectionContext.Disconnect();
            SetActiveConnection(null!);
        }
    }

    private Server ConnectServer(DbaInstanceParameter instance, PSCredential? credential, bool dac)
    {
        SmoConnectionRequest request = new()
        {
            Instance = instance,
            SqlCredential = credential,
            MinimumVersion = 9,
            AzureUnsupported = true,
            DedicatedAdminConnection = dac,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "SqlInstance", "SqlCredential", "MinimumVersion", "AzureUnsupported"
            },
            MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
        };
        if (dac)
            request.BoundParameters.Add("DedicatedAdminConnection");
        Server server = ConnectionService.GetServer(request);
        SetActiveConnection(server.ConnectionContext);
        return server;
    }

    private bool ConfirmAction(string target, string action)
    {
        if (!Force)
            return ShouldProcess(target, action);
        object? previous = SessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            SessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return ShouldProcess(target, action);
        }
        finally
        {
            SessionState.PSVariable.Set("ConfirmPreference", previous);
        }
    }

    private void CopyCredential(Server sourceServer, Server destinationServer, DbaInstanceParameter destination,
        SmoCredential credential, SqlCredentialSecrets? secrets)
    {
        string name = credential.Name;
        DbaDateTime timestamp = new(DateTime.Now);
        SmoCredential? existing = destinationServer.Credentials[name];
        if (existing is not null)
        {
            if (!Force)
            {
                if (ConfirmAction(destinationServer.Name, String.Format("Skipping {0}, already exists", name)))
                    WriteStatus(sourceServer, destinationServer, name, "Skipping", "Already exists on destination", timestamp);
                return;
            }
            if (ConfirmAction(destination.ToString(), String.Format("Dropping {0}", name)))
            {
                try { existing.Drop(); }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    // The pin reports drop failures only on the verbose stream.
                    WriteMessage(MessageLevel.Verbose, String.Format("Issue dropping {0} on {1} | {2}", name, destination, ex.Message));
                    return;
                }
            }
        }

        WriteMessage(MessageLevel.Verbose, String.Format("Attempting to migrate {0}", name));
        try
        {
            if (credential.MappedClassType == MappedClassType.CryptographicProvider &&
                !SqlCredentialSecrets.HasEnabledProvider(destinationServer, credential.ProviderName))
                throw new InvalidOperationException(String.Format(
                    "The cryptographic provider {0} needs to be configured and enabled on {1}", credential.ProviderName, destinationServer));

            string identityText = Identity is null ? "" : String.Join(" ", Identity);
            if (!ConfirmAction(destination.ToString(), String.Format("Copying {0} ({1})", identityText, name)))
                return;

            SmoCredential created = new(destinationServer, name);
            created.MappedClassType = credential.MappedClassType;
            created.ProviderName = credential.ProviderName;
            if (ExcludePassword)
            {
                WriteAttributedMessage("New-DbaCredential", MessageLevel.Verbose,
                    String.Format("Password was not provided, creating credential with identity '{0}' without password", credential.Identity));
                created.Create(credential.Identity);
            }
            else
            {
                WriteAttributedMessage("New-DbaCredential", MessageLevel.Verbose,
                    String.Format("Creating credential with identity '{0}' with password", credential.Identity));
                created.Create(credential.Identity, secrets!.GetSecret(name));
            }
            WriteMessage(MessageLevel.Verbose, String.Format("{0} successfully copied", name));
            WriteStatus(sourceServer, destinationServer, name, "Successful", null, timestamp);
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            // Copy-DbaCredential catches the nested creation failure even with EnableException.
            WriteStatus(sourceServer, destinationServer, name, "Failed", ex.Message, timestamp);
            WriteMessage(MessageLevel.Verbose, String.Format("Issue creating {0} on {1} | {2}", name, destination, ex.Message));
        }
    }

    private void WriteStatus(Server sourceServer, Server destinationServer, string name,
        string status, string? notes, DbaDateTime timestamp)
    {
        PSObject output = new();
        output.Properties.Add(new PSNoteProperty("SourceServer", SmoServerExtensions.GetDomainInstanceName(sourceServer)));
        output.Properties.Add(new PSNoteProperty("DestinationServer", SmoServerExtensions.GetDomainInstanceName(destinationServer)));
        output.Properties.Add(new PSNoteProperty("Type", "Credential"));
        output.Properties.Add(new PSNoteProperty("Name", name));
        output.Properties.Add(new PSNoteProperty("Status", status));
        output.Properties.Add(new PSNoteProperty("Notes", notes));
        output.Properties.Add(new PSNoteProperty("DateTime", timestamp));
        OutputHelper.SetDefaultDisplayPropertySet(output, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        OutputHelper.InsertTypeName(output, "MigrationObject");
        WriteObject(output);
    }
}
