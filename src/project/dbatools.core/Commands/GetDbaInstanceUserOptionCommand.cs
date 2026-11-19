#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaInstanceUserOption.ps1 at refs/pins/dbatools-2026-10-22: the connection, then each property of the
// instance's SMO UserOptions with the instance notes and the default view.
/// <summary>Retrieves instance-level user option defaults that affect new database connections</summary>
/// <para>
/// Returns the default user options configured at the SQL Server instance level that are automatically applied to new database connections. These settings include ANSI compliance options like ANSI_NULLS, QUOTED_IDENTIFIER, date format preferences, and other connection-level defaults. This is useful when standardizing connection behavior across environments or troubleshooting why applications behave differently on different instances. Unlike Get-DbaDbccUserOption which shows current session settings, this command shows the instance defaults that would be inherited by new connections.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaInstanceUserOption -SqlInstance localhost
/// </code>
/// <para>
/// Returns SQL Instance user options on the local default SQL Server instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaInstanceUserOption -SqlInstance sql2, sql4\sqlexpress
/// </code>
/// <para>
/// Returns SQL Instance user options on default instance on sql2 and sqlexpress instance on sql4
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'sql2','sql4' | Get-DbaInstanceUserOption
/// </code>
/// <para>
/// Returns SQL Instance user options on sql2 and sql4
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Instance, Configure, UserOption, General
/// Author: Klaas Vandenberghe (@powerdbaklaas)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaInstanceUserOption" />
[Cmdlet(VerbsCommon.Get, "DbaInstanceUserOption", DefaultParameterSetName = "Default")]
public sealed class GetDbaInstanceUserOptionCommand : DbaInstanceCmdlet
{
    // PS: Select-DefaultView -InputObject $prop -Property ComputerName, InstanceName, SqlInstance, Name, Value
    private static readonly string[] DisplaySet = { "ComputerName", "InstanceName", "SqlInstance", "Name", "Value" };

    // The note properties the pin adds with Add-Member -Force, in its order.
    private static readonly string[] AddedProperties = { "ComputerName", "InstanceName", "SqlInstance" };

    /// <para>
    /// The target SQL Server instance or instances.
    /// This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
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

    /// <summary>Reports the instance user options of each instance in this record.</summary>
    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
            {
                continue;
            }

            // PS: $props = $server.useroptions.properties; foreach ($prop in $props) { ... }
            List<Property>? options = ReadOptions(server);
            if (options is null)
            {
                continue;
            }

            foreach (Property option in options)
            {
                WriteObject(Decorate(option, server));
            }
        }
    }

    // SMO reads the options when the foreach enumerates the property collection. The pin has no try around that read: a
    // plain call writes the record and goes on with the next instance, a caller's try catches it, -EnableException stops
    // here.
    private List<Property>? ReadOptions(Server server)
    {
        List<Property> rows = new();
        IEnumerator? enumerator = null;
        ErrorRecord fault;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(server.UserOptions.Properties);
            while (enumerator is not null && enumerator.MoveNext())
            {
                rows.Add((Property)enumerator.Current);
            }

            return rows;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The engine's record when the failure carries one (ExceptionInGetEnumerator from GetEnumerator); otherwise the
            // record the engine makes of a plain exception from the foreach's MoveNext or Current: the exception itself, its
            // type's full name as the id, OperationStopped, no target.
            if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            {
                fault = new ErrorRecord(container.ErrorRecord, failure);
            }
            else
            {
                fault = new ErrorRecord(failure, failure.GetType().FullName, ErrorCategory.OperationStopped, null);
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

    // PS: Add-Member -Force of ComputerName, InstanceName and SqlInstance, then Select-DefaultView. SMO hands back the same
    // Property objects for the same Server object, and -Force replaces the notes an earlier call left on them.
    private static PSObject Decorate(Property option, Server server)
    {
        PSObject output = PSObject.AsPSObject(option);
        foreach (string name in AddedProperties)
        {
            output.Properties.Remove(name);
        }

        OutputHelper.AddInstanceProperties(output, server);
        OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
        return output;
    }
}
