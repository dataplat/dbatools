#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaInstanceTrigger.ps1 at refs/pins/dbatools-2026-10-22: the connection, then each server-level DDL
// trigger of the instance with the instance notes and the default view.
/// <summary>Retrieves server-level DDL triggers from SQL Server instances for auditing and documentation</summary>
/// <para>
/// Returns server-level DDL triggers that monitor and respond to instance-wide events like CREATE, ALTER, and DROP statements. Server triggers are commonly used for security auditing, change tracking, and preventing unauthorized schema modifications across all databases on an instance. This function helps identify what automated responses are configured at the server level, which is essential for troubleshooting unexpected DDL blocking and documenting compliance controls.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaInstanceTrigger -SqlInstance sql2017
/// </code>
/// <para>
/// Returns all server triggers on sql2017
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Database, Trigger, General
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaInstanceTrigger" />
[Cmdlet(VerbsCommon.Get, "DbaInstanceTrigger")]
public sealed class GetDbaInstanceTriggerCommand : DbaInstanceCmdlet
{
    // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, ID, Name, AnsiNullsStatus, AssemblyName,
    //     BodyStartIndex, ClassName, CreateDate, DateLastModified, DdlTriggerEvents, ExecutionContext, ExecutionContextLogin,
    //     ImplementationType, IsDesignMode, IsEnabled, IsEncrypted, IsSystemObject, MethodName, QuotedIdentifierStatus, State,
    //     TextHeader, TextMode
    private static readonly string[] DisplaySet =
    {
        "ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "AnsiNullsStatus", "AssemblyName", "BodyStartIndex",
        "ClassName", "CreateDate", "DateLastModified", "DdlTriggerEvents", "ExecutionContext", "ExecutionContextLogin",
        "ImplementationType", "IsDesignMode", "IsEnabled", "IsEncrypted", "IsSystemObject", "MethodName",
        "QuotedIdentifierStatus", "State", "TextHeader", "TextMode"
    };

    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance..
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <summary>Reports the server-level DDL triggers of each instance in this record.</summary>
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-refusal: Azure SQL Database has no server-level triggers, where the pin answers it with no row
            // and no word, as for an instance with none; it is refused as -AzureUnsupported does (fleet.md step 4).
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
            {
                continue;
            }

            // PS: foreach ($trigger in $server.Triggers) { ... }
            List<ServerDdlTrigger>? triggers = ReadTriggers(server);
            if (triggers is null)
            {
                continue;
            }

            foreach (ServerDdlTrigger trigger in triggers)
            {
                // PS: try { Add-Member ...; Select-DefaultView ... } catch { Stop-Function -Message "Failure" -ErrorRecord $_ -Continue }
                PSObject output;
                try
                {
                    output = Decorate(trigger, server);
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    StopFunction("Failure", errorRecord: new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null), continueLoop: true);
                    continue;
                }

                WriteObject(output);
            }
        }
    }

    // SMO loads the collection when the foreach enumerates it. The pin has no try around that read: a plain call writes the
    // record and goes on with the next instance, a caller's try catches it, -EnableException stops here.
    private List<ServerDdlTrigger>? ReadTriggers(Server server)
    {
        List<ServerDdlTrigger> rows = new();
        IEnumerator? enumerator = null;
        ErrorRecord fault;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(server.Triggers);
            while (enumerator is not null && enumerator.MoveNext())
            {
                rows.Add((ServerDdlTrigger)enumerator.Current);
            }

            return rows;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The engine's record when the failure carries one (ExceptionInGetEnumerator); otherwise the record a failing
            // MoveNext gives (BadEnumeration, InvalidOperation, the enumerator as target).
            if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            {
                fault = new ErrorRecord(container.ErrorRecord, failure);
            }
            else
            {
                RuntimeException enumeration = new(string.Format(CultureInfo.InvariantCulture,
                    "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
                fault = new ErrorRecord(enumeration, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
            }
        }

        SurfaceFault(fault);
        return null;
    }

    // A read in the pin's body, which has no try around it: a plain call writes it and goes on, a caller's try catches it,
    // -EnableException stops here.
    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a read's statement fault, outside Stop-Function, as in the pin
        }

        StatementFault.Surface(this, fault);
    }

    // PS: Add-Member -Force of ComputerName, InstanceName and SqlInstance, then Select-DefaultView. -Force replaces the notes
    // an earlier call left on the same SMO object.
    private static PSObject Decorate(ServerDdlTrigger trigger, Server server)
    {
        PSObject output = PSObject.AsPSObject(trigger);
        foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
        {
            output.Properties.Remove(name);
        }

        OutputHelper.AddInstanceProperties(output, server);
        OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
        return output;
    }
}
