#nullable enable

using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaConnectedInstance.ps1 at refs/pins/dbatools-2026-10-22. The pinned
// $script:connectionhash is the process-wide ConnectionHost.ActiveConnections registry that
// Connect-DbaInstance fills (ConnectionService.RegisterConnection, Add-ConnectionHashValue parity):
// each key is a connection string, each value the list of Server or SqlConnection objects for it.
/// <summary>Returns SQL Server instances currently cached in the dbatools connection pool</summary>
/// <para>
/// Shows all SQL Server connections that are currently active or cached in your PowerShell session. When you connect to instances using dbatools commands like Connect-DbaInstance, those connections are stored in an internal cache for reuse. This command reveals what's in that cache, including connection details like whether pooling is enabled and the connection type (SMO server objects vs raw SqlConnection objects). Use this to track active connections before cleaning them up with Disconnect-DbaInstance or to troubleshoot connection-related issues in long-running scripts.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaConnectedInstance
/// </code>
/// <para>
/// Gets all connected SQL Server instances
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaConnectedInstance | Select *
/// </code>
/// <para>
/// Gets all connected SQL Server instances and shows the associated connectionstrings as well
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Connection
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2021 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaConnectedInstance" />
[Cmdlet(VerbsCommon.Get, "DbaConnectedInstance")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaConnectedInstanceCommand : DbaBaseCmdlet
{
    // PS: Select-DefaultView -Property SqlInstance, ConnectionType, ConnectionObject, Pooled
    private static readonly string[] DisplaySet = { "SqlInstance", "ConnectionType", "ConnectionObject", "Pooled" };

    // The pinned function declares param () under [CmdletBinding()]: no EnableException. Overridden
    // without [Parameter] so the inherited switch is not a parameter of this cmdlet (the binder reads
    // the most-derived declaration's attributes); nothing here stops, so it is never read.
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        // PS: foreach ($key in $script:connectionhash.Keys)
        // Correction cache-snapshot: copy the entries before the first row is written, so a command
        // downstream that connects or disconnects cannot end the listing (the pinned enumeration of the
        // live cache failed with "Collection was modified" and never listed the rest).
        List<KeyValuePair<string, object[]>> snapshot = new List<KeyValuePair<string, object[]>>();
        foreach (KeyValuePair<string, List<object>> cached in ConnectionHost.ActiveConnections)
        {
            // PS: @($Value) - the pinned cache holds an object[] per key.
            snapshot.Add(new KeyValuePair<string, object[]>(cached.Key, cached.Value?.ToArray() ?? new object[0]));
        }

        foreach (KeyValuePair<string, object[]> cached in snapshot)
        {
            string key = cached.Key;
            object[] entries = cached.Value;

            // PS: if ($script:connectionhash[$key].DataSource) { ... -ExpandProperty DataSource } else { ... -ExpandProperty Name }
            object? instance = PsProperty.Get(First(entries), HasDataSource(entries) ? "DataSource" : "Name");

            // PS: $value = $script:connectionhash[$key] | Select-Object -First 1
            object? value = First(entries);
            if (value is null)
            {
                // PS: an empty cache entry leaves $value $null and $value.GetType() fails the statement;
                // the foreach continues with the next key. Connect-DbaInstance never stores an empty entry.
                WriteError(new ErrorRecord(new RuntimeException("You cannot call a method on a null-valued expression."),
                    "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null));
                continue;
            }

            // PS: if ($value.ConnectionContext.NonPooledConnection -or $value.NonPooledConnection) { $pooling = $false } else { $pooling = $true }
            bool nonPooled = PsOps.IsTrue(PsProperty.Get(PsProperty.Get(value, "ConnectionContext"), "NonPooledConnection"))
                || PsOps.IsTrue(PsProperty.Get(value, "NonPooledConnection"));

            // Correction sqlconnection-pooled: a SqlConnection has neither property, so the pinned test
            // always called it pooled; its own connection string says whether SqlClient pools it.
            if ((value is PSObject wrappedValue ? wrappedValue.BaseObject : value) is SqlConnection sqlConnection)
            {
                nonPooled = !new SqlConnectionStringBuilder(sqlConnection.ConnectionString).Pooling;
            }

            PSObject output = new PSObject();
            output.Properties.Add(new PSNoteProperty("SqlInstance", instance));
            output.Properties.Add(new PSNoteProperty("ConnectionObject", entries));
            output.Properties.Add(new PSNoteProperty("ConnectionType", (value is PSObject wrapped ? wrapped.BaseObject : value).GetType().FullName));
            output.Properties.Add(new PSNoteProperty("Pooled", !nonPooled));
            output.Properties.Add(new PSNoteProperty("ConnectionString", ConnectionService.HideConnectionString(key)));
            OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
            WriteObject(output);
        }
    }

    private static object? First(object[] entries)
    {
        return entries.Length > 0 ? entries[0] : null;
    }

    // PS: $array.DataSource is member-access enumeration: the DataSource values of the elements that
    // have one (an SMO Server has none). Its truth: none is false, one is that value's truth, more is true.
    private static bool HasDataSource(object[] entries)
    {
        List<object?> values = new List<object?>();
        foreach (object entry in entries)
        {
            if (PsProperty.Has(entry, "DataSource"))
            {
                values.Add(PsProperty.Get(entry, "DataSource"));
            }
        }
        return values.Count > 1 || (values.Count == 1 && PsOps.IsTrue(values[0]));
    }
}
