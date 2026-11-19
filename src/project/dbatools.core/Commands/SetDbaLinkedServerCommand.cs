#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters the connection-behaviour options of an existing linked server. NEW designed command -
/// no PS ancestor, pure C#, no hop. Completes the linked-server CRUD family (New-/Get-/Remove-
/// exist; no Set- did). Surface pinned by migration/designed/Set-DbaLinkedServer.json (signed).
///
/// SMO. LinkedServer.Alter() (Smo/LinkedServerBase.cs:201). The alterable surface is defined
/// exactly by ScriptAlter (:207-238), which emits sp_serveroption for CollationCompatible,
/// DataAccess, Distributor, Publisher, Rpc, RpcOut, Subscriber and - for target >= 8.0 -
/// ConnectTimeout, CollationName, LazySchemaValidation, QueryTimeout, UseRemoteCollation. Those
/// twelve options are this command's option surface. DistPublisher is excluded (8.0-only, hard 0
/// on 2005+) and IsPromotionofDistributedTransactionsForRPCEnabled is held out of v1.
///
/// READ-ONLY-AFTER-CREATION properties are NOT on the surface. Catalog/DataSource/ProductName/
/// ProviderName/ProviderString and Location are ReadOnlyAfterCreation (SqlEnum/xml/
/// linkedserver.xml), and CheckNonAlterableProperties (Smo/SqlSmoObject.cs:1143-1154) THROWS at
/// Alter() if any is dirty, so a parameter for them could only ever throw. Name is the read-only
/// key, so there is no -NewName either. Changing those requires drop-and-recreate.
///
/// DIRTY-GATE. GetStringOption (LinkedServerBase.cs:245) emits an option only when the property is
/// non-null AND dirty, so setting an option to its current value is a genuine no-op; the command
/// still re-emits the refreshed object. Boolean options are SWITCHES per CLAUDE.md, applied only
/// when BOUND: -Rpc:$false turns an option off, an unbound -Rpc leaves it untouched - the single
/// most likely regression, and it has its own test.
///
/// DUALITY. No parameter sets. ProcessRecord runs TestBound(SqlInstance, InputObject) and
/// StopFunction("You must supply either -SqlInstance or an Input Object"); -LinkedServer is
/// required alongside -SqlInstance, mirroring the guard in the retired New-DbaLinkedServer.
///
/// OUTPUT. Re-emits the refreshed Smo.LinkedServer decorated exactly like Get-DbaLinkedServer -
/// ComputerName/InstanceName/SqlInstance plus Impersonate and RemoteUser NoteProperties pulled
/// from LinkedServerLogins, and a default view carrying the 'DataSource as RemoteServer' and
/// 'DistPublisher as Publisher' aliases. Replace-then-add, because a piped-in object from the
/// getCounterpart is already decorated.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaLinkedServer", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.LinkedServer))]
public sealed class SetDbaLinkedServerCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The linked server(s) to alter on the target instance.</summary>
    [Parameter(Position = 2)]
    public string[]? LinkedServer { get; set; }

    /// <summary>SMO LinkedServer object(s) from Get-DbaLinkedServer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Microsoft.SqlServer.Management.Smo.LinkedServer[]? InputObject { get; set; }

    /// <summary>Whether the collation of the linked server is compatible with the local server.</summary>
    [Parameter]
    public SwitchParameter CollationCompatible { get; set; }

    /// <summary>The collation name the linked server uses (target >= 8.0).</summary>
    [Parameter]
    public string? CollationName { get; set; }

    /// <summary>Seconds to wait before timing out a connection attempt (target >= 8.0).</summary>
    [Parameter]
    public int ConnectTimeout { get; set; }

    /// <summary>Whether the linked server is enabled for data access (distributed queries).</summary>
    [Parameter]
    public SwitchParameter DataAccess { get; set; }

    /// <summary>Whether the linked server is a distributor.</summary>
    [Parameter]
    public SwitchParameter Distributor { get; set; }

    /// <summary>Whether SQL Server sends the schema to the provider lazily (target >= 8.0).</summary>
    [Parameter]
    public SwitchParameter LazySchemaValidation { get; set; }

    /// <summary>Whether the linked server is a publisher.</summary>
    [Parameter]
    public SwitchParameter Publisher { get; set; }

    /// <summary>Seconds to wait before timing out a query (target >= 8.0).</summary>
    [Parameter]
    public int QueryTimeout { get; set; }

    /// <summary>Whether the linked server is enabled for RPC.</summary>
    [Parameter]
    public SwitchParameter Rpc { get; set; }

    /// <summary>Whether the linked server is enabled for RPC out.</summary>
    [Parameter]
    public SwitchParameter RpcOut { get; set; }

    /// <summary>Whether the linked server is a subscriber.</summary>
    [Parameter]
    public SwitchParameter Subscriber { get; set; }

    /// <summary>Whether queries use the collation of the remote server rather than the local one (target >= 8.0).</summary>
    [Parameter]
    public SwitchParameter UseRemoteCollation { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Either/or duality with no parameter sets. The check lives in ProcessRecord rather than
        // BeginProcessing because a pipeline-bound InputObject does not appear in BoundParameters
        // until ProcessRecord - a Begin-time check would false-fail pure pipeline usage.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        // Feeder 1: resolve linked servers from -SqlInstance. -LinkedServer identifies them here
        // (mirroring the retired New-DbaLinkedServer's LinkedServer-required guard); it is NOT
        // required on the pipeline path, where the piped object IS the linked server.
        if (TestBound(nameof(SqlInstance)))
        {
            if (LinkedServer is null || LinkedServer.Length == 0)
            {
                StopFunction("LinkedServer is required when SqlInstance is specified");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server? server = ConnectInstance(instance, "Failure");
                if (server is null)
                {
                    continue;
                }

                foreach (Microsoft.SqlServer.Management.Smo.LinkedServer linkedServer in ResolveLinkedServers(server))
                {
                    ProcessLinkedServer(linkedServer);
                }
            }
        }

        // Feeder 2: LinkedServer objects piped from Get-DbaLinkedServer. The parent server is
        // resolved PER RECORD (linkedServer.Parent) - never carried across records.
        foreach (Microsoft.SqlServer.Management.Smo.LinkedServer linkedServer in InputObject ?? Array.Empty<Microsoft.SqlServer.Management.Smo.LinkedServer>())
        {
            ProcessLinkedServer(linkedServer);
        }
    }

    // One worker, two feeders.
    private void ProcessLinkedServer(Microsoft.SqlServer.Management.Smo.LinkedServer linkedServer)
    {
        Server? server = linkedServer.Parent;
        if (server is null)
        {
            StopFunction(String.Format("Linked server {0} has no parent server", linkedServer.Name),
                target: linkedServer, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        // ShouldProcess string is VERBATIM from the signed spec's shouldProcessTargets.
        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
        string action = String.Format("Altering linked server {0}", linkedServer.Name);
        if (!ShouldProcess(target, action))
        {
            return;
        }

        try
        {
            // Apply ONLY explicitly-bound options - an unbound option must mean "leave unchanged".
            // Boolean options are switches read via TestBound so -X:$false turns the option off.
            if (TestBound(nameof(CollationCompatible)))
            {
                linkedServer.CollationCompatible = CollationCompatible.ToBool();
            }
            if (TestBound(nameof(DataAccess)))
            {
                linkedServer.DataAccess = DataAccess.ToBool();
            }
            if (TestBound(nameof(Distributor)))
            {
                linkedServer.Distributor = Distributor.ToBool();
            }
            if (TestBound(nameof(Publisher)))
            {
                linkedServer.Publisher = Publisher.ToBool();
            }
            if (TestBound(nameof(Rpc)))
            {
                linkedServer.Rpc = Rpc.ToBool();
            }
            if (TestBound(nameof(RpcOut)))
            {
                linkedServer.RpcOut = RpcOut.ToBool();
            }
            if (TestBound(nameof(Subscriber)))
            {
                linkedServer.Subscriber = Subscriber.ToBool();
            }
            if (TestBound(nameof(LazySchemaValidation)))
            {
                linkedServer.LazySchemaValidation = LazySchemaValidation.ToBool();
            }
            if (TestBound(nameof(UseRemoteCollation)))
            {
                linkedServer.UseRemoteCollation = UseRemoteCollation.ToBool();
            }
            if (TestBound(nameof(CollationName)))
            {
                linkedServer.CollationName = CollationName;
            }
            if (TestBound(nameof(ConnectTimeout)))
            {
                linkedServer.ConnectTimeout = ConnectTimeout;
            }
            if (TestBound(nameof(QueryTimeout)))
            {
                linkedServer.QueryTimeout = QueryTimeout;
            }

            linkedServer.Alter();
            linkedServer.Refresh();
        }
        catch (Exception ex)
        {
            StopFunction(String.Format("Failure altering linked server {0} on {1}", linkedServer.Name, server.Name),
                target: linkedServer,
                errorRecord: new ErrorRecord(ex, "dbatools_SetDbaLinkedServer", ErrorCategory.InvalidOperation, linkedServer),
                continueLoop: true);
            return;
        }

        WriteLinkedServer(linkedServer, server);
    }

    // Decorated exactly like Get-DbaLinkedServer so Get -> Set -> Get composes. Replace-then-add:
    // anything piped in from the getCounterpart is ALREADY decorated and a plain Add would throw
    // on a duplicate member name.
    private void WriteLinkedServer(Microsoft.SqlServer.Management.Smo.LinkedServer linkedServer, Server server)
    {
        PSObject wrapped = PSObject.AsPSObject(linkedServer);
        ReplaceNoteProperty(wrapped, "ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server));
        ReplaceNoteProperty(wrapped, "Impersonate", CollectLoginMember(linkedServer, "Impersonate"));
        ReplaceNoteProperty(wrapped, "RemoteUser", CollectLoginMember(linkedServer, "RemoteUser"));
        // 'DataSource as RemoteServer' and 'DistPublisher as Publisher' aliases from
        // Get-DbaLinkedServer's Select-DefaultView. That view's Add-Member uses -Force
        // -ErrorAction SilentlyContinue, so the alias-add is best-effort - reproduced here.
        TryAddAlias(wrapped, "RemoteServer", "DataSource");
        TryAddAlias(wrapped, "Publisher", "DistPublisher");
        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "Name", "RemoteServer", "ProductName",
            "Impersonate", "RemoteUser", "Publisher", "Distributor", "DateLastModified");
        WriteObject(wrapped);
    }

    // Mirrors Get-DbaLinkedServer's $ls.LinkedServerLogins.<member> PowerShell member enumeration:
    // nothing for an empty collection, the scalar for one login, an array for several.
    private static object? CollectLoginMember(Microsoft.SqlServer.Management.Smo.LinkedServer linkedServer, string member)
    {
        List<object?> values = new();
        foreach (Microsoft.SqlServer.Management.Smo.LinkedServerLogin login in linkedServer.LinkedServerLogins)
        {
            values.Add(member == "Impersonate" ? login.Impersonate : login.RemoteUser);
        }

        if (values.Count == 0)
        {
            return null;
        }
        if (values.Count == 1)
        {
            return values[0];
        }
        return values.ToArray();
    }

    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        if (wrapped.Properties[name] is PSNoteProperty)
        {
            wrapped.Properties.Remove(name);
        }
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }

    private static void TryAddAlias(PSObject wrapped, string aliasName, string referencedName)
    {
        try
        {
            if (wrapped.Properties[aliasName] is PSAliasProperty)
            {
                wrapped.Properties.Remove(aliasName);
            }
            wrapped.Properties.Add(new PSAliasProperty(aliasName, referencedName));
        }
        catch
        {
            // Select-DefaultView adds these aliases with -ErrorAction SilentlyContinue; a name that
            // collides with an unremovable adapted member simply leaves the real property showing.
        }
    }

    // Not a lazy iterator ON PURPOSE: a requested-but-missing linked server must be REPORTED
    // (warn + continue, terminating under -EnableException), never silently skipped.
    private List<Microsoft.SqlServer.Management.Smo.LinkedServer> ResolveLinkedServers(Server server)
    {
        List<Microsoft.SqlServer.Management.Smo.LinkedServer> resolved = new();

        foreach (string linkedServerName in LinkedServer ?? Array.Empty<string>())
        {
            Microsoft.SqlServer.Management.Smo.LinkedServer? linkedServer = server.LinkedServers[linkedServerName];
            if (linkedServer is null)
            {
                StopFunction(String.Format("Linked server {0} does not exist on {1}", linkedServerName, server.Name),
                    target: linkedServerName, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            resolved.Add(linkedServer);
        }

        return resolved;
    }
}
