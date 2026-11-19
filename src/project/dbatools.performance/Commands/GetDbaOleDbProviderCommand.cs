#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves OLE DB provider configurations registered with SQL Server for linked servers and distributed queries
/// </summary>
/// <para>
/// Returns the OLE DB providers that SQL Server knows about and can use for external data connections like linked servers, distributed queries, and OPENROWSET operations. This is essential for auditing your server's connectivity capabilities and troubleshooting linked server connection issues. The function shows provider details including security settings like AllowInProcess and DisallowAdHocAccess, which control how SQL Server can use each provider. Use this when setting up linked servers or diagnosing why certain external data sources aren't accessible.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaOleDbProvider -SqlInstance SqlBox1\Instance2
/// </code>
/// <para>
/// Returns a list of all OleDb providers on SqlBox1\Instance2
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaOleDbProvider -SqlInstance SqlBox1\Instance2 -Provider SSISOLEDB
/// </code>
/// <para>
/// Returns the SSISOLEDB provider on SqlBox1\Instance2
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: General, OLEDB
/// Author: Chrissy LeMaire (@cl)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2021 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaOleDbProvider" />
// Port of public/Get-DbaOleDbProvider.ps1 at refs/pins/dbatools-2026-10-22: each instance's Settings.OleDbProviderSettings,
// optionally filtered by name, each provider decorated with ComputerName, InstanceName and SqlInstance and the pinned
// default display columns.
[Cmdlet(VerbsCommon.Get, "DbaOleDbProvider", DefaultParameterSetName = "Default")]
public sealed class GetDbaOleDbProviderCommand : DbaInstanceCmdlet
{
    // PS: Select-DefaultView -Property 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Description', 'AllowInProcess',
    //     'DisallowAdHocAccess', 'DynamicParameters', 'IndexAsAccessPath', 'LevelZeroOnly', 'NestedQueries', 'NonTransactedUpdates'
    private static readonly string[] DisplaySet =
    {
        "ComputerName", "InstanceName", "SqlInstance", "Name", "Description", "AllowInProcess", "DisallowAdHocAccess",
        "DynamicParameters", "IndexAsAccessPath", "LevelZeroOnly", "NestedQueries", "NonTransactedUpdates"
    };

    // The note properties the pin adds with Add-Member -Force, in its order.
    private static readonly string[] AddedProperties = { "ComputerName", "InstanceName", "SqlInstance" };

    /// <summary>
    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    /// </summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>
    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    /// </summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>
    /// <para>
    /// Filters results to specific OLE DB provider names. Accepts an array of provider names for targeting multiple providers.
    /// Use this when you need to check configuration for specific providers like SQLNCLI11 or MSDASQL instead of listing all available providers.
    /// </para>
    /// </summary>
    [Parameter(Position = 2)]
    public string[]? Provider { get; set; }

    /// <summary>
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    /// </summary>
    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-refusal: OLE DB providers serve linked servers and distributed queries, which Azure SQL Database
            // does not have; the instance is refused as Connect-DbaInstance -AzureUnsupported refuses it (fleet.md step 4).
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
            {
                continue;
            }

            // PS: Write-Message -Level Verbose -Message "Getting startup procedures for $servername"; the function never assigns
            // $servername, so the read leaves the function for the module scope, which does not define it, then the global one.
            WriteMessage(MessageLevel.Verbose, "Getting startup procedures for " + InterpolatedText(SessionState.PSVariable.GetValue("global:servername")));

            // PS: $providers = $server.Settings.OleDbProviderSettings, then the -Provider filter and the foreach enumerate it.
            // While $providers still holds the collection (no filter ran, or the filter statement failed), each statement
            // reads it again.
            object? collection = ReadCollection(server);
            List<OleDbProviderSettings>? providers = null;
            if (IsTrue(Provider))
            {
                // PS: $providers = $providers | Where-Object Name -in $Provider
                List<OleDbProviderSettings>? all = ReadProviders(collection, providers);
                if (all is not null)
                {
                    providers = all.FindAll(candidate => NameIn(candidate.Name, Provider));
                }
            }

            // PS: foreach ($oledbprovider in $providers)
            List<OleDbProviderSettings>? selected = ReadProviders(collection, providers);
            if (selected is null)
            {
                continue;
            }

            foreach (OleDbProviderSettings oleDbProvider in selected)
            {
                WriteProvider(oleDbProvider, server);
            }
        }
    }

    // PS: $server.Settings.OleDbProviderSettings, a read of two SMO properties. PowerShell gives null for a property whose
    // getter throws, and SMO's do throw where the engine has no such object (UnsupportedVersionException); the foreach of a
    // null then writes nothing.
    private static object? ReadCollection(Server server)
    {
        try
        {
            return server.Settings?.OleDbProviderSettings;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return null;
        }
    }

    // The statement's read of $providers: the filtered list once a filter has run, else the collection, enumerated as the
    // engine enumerates it. A failed enumeration is the engine's statement fault; the pin writes it and goes on to the next
    // statement. A null collection holds nothing.
    private List<OleDbProviderSettings>? ReadProviders(object? collection, List<OleDbProviderSettings>? current)
    {
        if (current is not null)
        {
            return current;
        }

        List<OleDbProviderSettings> providers = new();
        if (collection is null)
        {
            return providers;
        }

        IEnumerator? enumerator = null;
        ErrorRecord fault;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(collection);
            while (enumerator is not null && enumerator.MoveNext())
            {
                providers.Add((OleDbProviderSettings)enumerator.Current);
            }

            return providers;
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

        ReportFault(fault);
        return null;
    }

    // Accepted difference kept by the keep-going section's point 3: -EnableException stops here with this record, where
    // the pin writes it and goes on; -ErrorAction Stop has the effect PowerShell gives WriteError.
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        // A plain call goes on; under a caller try the record stops the command, as the fault stops the pin's statement.
        StatementFault.Surface(this, fault);
    }

    // PS: the foreach body - Add-Member -Force of three note properties on the SMO object, then Select-DefaultView.
    private void WriteProvider(OleDbProviderSettings oleDbProvider, Server server)
    {
        PSObject output = PSObject.AsPSObject(oleDbProvider);
        foreach (string property in AddedProperties)
        {
            output.Properties.Remove(property);
        }

        OutputHelper.AddInstanceProperties(output, server);
        OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
        WriteObject(output);
    }

    // PS: if ($Provider) - an array is false when empty, its element's truthiness with one element, true with more.
    private static bool IsTrue(string[]? values)
    {
        if (values is null || values.Length == 0)
        {
            return false;
        }

        if (values.Length == 1)
        {
            return LanguagePrimitives.IsTrue(values[0]);
        }

        return true;
    }

    // Where-Object Name -in <names>: the engine's equality, ignoring case; a null list holds nothing.
    private static bool NameIn(string name, string[]? names)
    {
        if (names is null)
        {
            return false;
        }

        foreach (string candidate in names)
        {
            if (LanguagePrimitives.Equals(candidate, name, true, CultureInfo.InvariantCulture))
            {
                return true;
            }
        }

        return false;
    }

    // A variable's value as a double-quoted string expands it; null expands to nothing.
    private static string InterpolatedText(object? value)
    {
        if (value is null)
        {
            return string.Empty;
        }

        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
    }
}
