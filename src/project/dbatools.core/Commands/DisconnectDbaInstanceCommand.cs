#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Closes active SQL Server connections and removes them from the dbatools connection cache
/// </summary>
[Cmdlet(VerbsCommunications.Disconnect, "DbaInstance", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class DisconnectDbaInstanceCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server connection object(s) to disconnect (SMO Server, SqlConnection, or Get-DbaConnectedInstance rows).</summary>
    [Parameter(Position = 0, ValueFromPipeline = true)]
    public PSObject?[]? InputObject { get; set; }

    private List<object?> _objects = null!;

    protected override void BeginProcessing()
    {
        _objects = new List<object?>();
    }

    protected override void ProcessRecord()
    {
        // PS: $objects += $InputObject — the uninitialized $objects grows per block; an
        // unbound/absent InputObject appends one $null element (harmless downstream).
        if (InputObject is null)
        {
            _objects.Add(null);
            return;
        }
        foreach (PSObject? element in InputObject)
        {
            _objects.Add(element);
        }
    }

    protected override void EndProcessing()
    {
        foreach (object? inputItem in _objects)
        {
            // PS: if ($object.ConnectionObject) { $servers = $object.ConnectionObject } else { $servers = $object }
            // — the truthiness test and the assignment are two INDEPENDENT property reads
            // (a volatile getter can differ between them).
            object? servers = PsOps.IsTrue(PsProperty.Get(inputItem, "ConnectionObject"))
                ? PsProperty.Get(inputItem, "ConnectionObject")
                : inputItem;

            foreach (object? server in EnumeratePs(servers))
            {
                try
                {
                    // PS: if ($server.ConnectionContext) — SMO Server (and friends) branch.
                    // Every $server.ConnectionContext / .ConnectionString below is its own
                    // fresh property read, exactly like the PS dot-access expressions.
                    if (PsOps.IsTrue(PsProperty.Get(server, "ConnectionContext")))
                    {
                        string serverName = PsText(PsProperty.Get(server, "Name"));
                        if (ShouldProcess(serverName, "Disconnecting SQL Connection"))
                        {
                            // PS: $null = $server.ConnectionContext.Disconnect() — dynamic
                            // method invocation on the freshly read property value; a null
                            // re-read fails the method call into the catch like PS does.
                            InvokePsMethod(PsProperty.Get(server, "ConnectionContext"), "Disconnect");

                            // PS: registry lookup, removal, and the masked output each read
                            // $server.ConnectionContext.ConnectionString AGAIN.
                            if (RegistryEntryIsTruthy(ToPsString(PsProperty.Get(PsProperty.Get(server, "ConnectionContext"), "ConnectionString"))))
                            {
                                WriteMessage(MessageLevel.Verbose, "removing from connection hash");
                                RemoveRegistryEntry(ToPsString(PsProperty.Get(PsProperty.Get(server, "ConnectionContext"), "ConnectionString")));
                            }

                            PSObject result = new PSObject();
                            result.Properties.Add(new PSNoteProperty("SqlInstance", PsProperty.Get(server, "Name")));
                            result.Properties.Add(new PSNoteProperty("ConnectionString", ConnectionService.HideConnectionString(ToPsString(PsProperty.Get(PsProperty.Get(server, "ConnectionContext"), "ConnectionString")))));
                            result.Properties.Add(new PSNoteProperty("ConnectionType", GetTypePs(server).FullName));
                            result.Properties.Add(new PSNoteProperty("State", "Disconnected"));
                            OutputHelper.SetDefaultDisplayPropertySet(result, "SqlInstance", "ConnectionType", "State");
                            WriteObject(result);
                        }
                    }

                    // PS: if ($server.GetType().Name -eq "SqlConnection") — NAME match, so both
                    // System.Data.SqlClient and Microsoft.Data.SqlClient connections qualify.
                    // GetType() on a null $server throws into the catch (PS method-on-null).
                    Type serverType = GetTypePs(server);
                    if (PsString.Eq(serverType.Name, "SqlConnection"))
                    {
                        string dataSource = PsText(PsProperty.Get(server, "DataSource"));
                        if (ShouldProcess(dataSource, "Closing SQL Connection"))
                        {
                            // PS: if ($server.State -eq "Open") { $null = $server.Close() }
                            if (PsOps.Eq(PsProperty.Get(server, "State"), "Open"))
                            {
                                InvokePsMethod(server, "Close");
                            }

                            if (RegistryEntryIsTruthy(ToPsString(PsProperty.Get(server, "ConnectionString"))))
                            {
                                WriteMessage(MessageLevel.Verbose, "removing from connection hash");
                                RemoveRegistryEntry(ToPsString(PsProperty.Get(server, "ConnectionString")));
                            }

                            PSObject result = new PSObject();
                            result.Properties.Add(new PSNoteProperty("SqlInstance", PsProperty.Get(server, "DataSource")));
                            result.Properties.Add(new PSNoteProperty("ConnectionString", ConnectionService.HideConnectionString(ToPsString(PsProperty.Get(server, "ConnectionString")))));
                            result.Properties.Add(new PSNoteProperty("ConnectionType", serverType.FullName));
                            // PS reads State AFTER the close, so the live enum value is emitted.
                            result.Properties.Add(new PSNoteProperty("State", PsProperty.Get(server, "State")));
                            OutputHelper.SetDefaultDisplayPropertySet(result, "SqlInstance", "ConnectionType", "State");
                            WriteObject(result);
                        }
                    }
                }
                catch (Exception ex)
                {
                    // PS: Stop-Function -Message "Failed to disconnect $object" -ErrorRecord $PSItem -Continue
                    StopFunction(String.Format("Failed to disconnect {0}", PsInterpolate(inputItem)),
                        errorRecord: new ErrorRecord(ex, "Disconnect-DbaInstance", ErrorCategory.NotSpecified, inputItem),
                        continueLoop: true);
                    continue;
                }
            }
        }
    }

    /// <summary>
    /// PS: $server.GetType() — throws the method-on-null error into the enclosing catch when
    /// the enumerated element is null (property access on null is fine; the method call is not).
    /// </summary>
    private static Type GetTypePs(object? server)
    {
        if (server is null)
        {
            throw new PSInvalidOperationException("You cannot call a method on a null-valued expression.");
        }
        return server is PSObject wrapped ? wrapped.BaseObject.GetType() : server.GetType();
    }

    /// <summary>
    /// PS string conversion for the dictionary indexer / [string] helper binding: a non-string
    /// ConnectionString value (StringBuilder etc.) converts like LanguagePrimitives does; null
    /// stays null.
    /// </summary>
    private static string? ToPsString(object? value)
    {
        if (value is null)
        {
            return null;
        }
        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
    }

    /// <summary>
    /// PS: [Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections[$key] truthiness —
    /// a missing key reads null (falsy), a present-but-empty list is falsy and left in place.
    /// A null key returns falsy without the indexer's error record (statement residual).
    /// </summary>
    private static bool RegistryEntryIsTruthy(string? connectionString)
    {
        if (connectionString is null)
        {
            return false;
        }
        return ConnectionHost.ActiveConnections.TryGetValue(connectionString, out List<object>? registered) && PsOps.IsTrue(registered);
    }

    private static void RemoveRegistryEntry(string? connectionString)
    {
        if (connectionString is null)
        {
            return;
        }
        ConnectionHost.ActiveConnections.Remove(connectionString);
    }

    /// <summary>PS foreach semantics: null iterates zero times, a collection enumerates, a scalar iterates once.</summary>
    private static IEnumerable<object?> EnumeratePs(object? value)
    {
        if (value is null)
        {
            yield break;
        }
        object baseValue = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (baseValue is not string && LanguagePrimitives.GetEnumerable(baseValue) is IEnumerable elements)
        {
            foreach (object? element in elements)
            {
                yield return element;
            }
            yield break;
        }
        yield return value;
    }

    /// <summary>
    /// PS dynamic method invocation (member binder resolution over the PSObject). A null
    /// target throws the PS method-on-null error into the enclosing catch.
    /// </summary>
    private static void InvokePsMethod(object? target, string methodName)
    {
        if (target is null)
        {
            throw new PSInvalidOperationException("You cannot call a method on a null-valued expression.");
        }
        PSMethodInfo? method = PSObject.AsPSObject(target).Methods[methodName];
        if (method is null)
        {
            // PS: calling a missing method is a statement-terminating error the enclosing
            // catch turns into the Stop-Function warning; the message names the BASE type
            // (a property bag reads as PSCustomObject, exactly like the PS binder text).
            object baseTarget = target is PSObject wrapped ? wrapped.BaseObject : target;
            throw new PSInvalidOperationException(String.Format("Method invocation failed because [{0}] does not contain a method named '{1}'.", baseTarget.GetType().FullName, methodName));
        }
        method.Invoke();
    }

    /// <summary>
    /// PS expandable-string rendering of a value: LanguagePrimitives conversion (invariant
    /// numerics, bag rendering), enumerables joined with the session $OFS, null empty — the
    /// campaign interpolation semantics (ConvertTo-DbaTimeline precedent).
    /// </summary>
    private string PsText(object? value)
    {
        return Dataplat.Dbatools.Utility.PowerShellText.Expand(value, SessionState);
    }

    /// <summary>PS "$object" interpolation for the Stop-Function message.</summary>
    private string PsInterpolate(object? value)
    {
        return PsText(value);
    }
}
