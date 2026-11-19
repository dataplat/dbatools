#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoAudit = Microsoft.SqlServer.Management.Smo.Audit;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server audit objects from instance-level security auditing configurations.
/// </summary>
/// <para>
/// Retrieves all configured SQL Server audit objects at the instance level, which define where security audit events are stored and how they're managed. These audits capture login attempts, permission changes, and other security-related activities across the entire SQL Server instance. The function returns detailed information including audit file paths, size limits, rollover settings, and current status, helping DBAs monitor compliance and troubleshoot security configurations without manually querying system views.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaInstanceAudit -SqlInstance localhost
/// </code>
/// <para>
/// Returns all Security Audits on the local default SQL Server instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaInstanceAudit -SqlInstance localhost, sql2016
/// </code>
/// <para>
/// Returns all Security Audits for the local and sql2016 SQL Server instances
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Audit, Security, SqlAudit
/// Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaInstanceAudit" />
[Cmdlet(VerbsCommon.Get, "DbaInstanceAudit")]
[OutputType(typeof(SmoAudit))]
public sealed class GetDbaInstanceAuditCommand : DbaInstanceCmdlet
{
    // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Name, 'Enabled as IsEnabled', OnFailure,
    //     MaximumFiles, MaximumFileSize, MaximumFileSizeUnit, MaximumRolloverFiles, QueueDelay, ReserveDiskSpace, FullName
    private static readonly string[] DisplaySet =
    {
        "ComputerName", "InstanceName", "SqlInstance", "Name", "IsEnabled", "OnFailure", "MaximumFiles", "MaximumFileSize",
        "MaximumFileSizeUnit", "MaximumRolloverFiles", "QueueDelay", "ReserveDiskSpace", "FullName"
    };

    // The note properties the pin adds with Add-Member -Force, in its order.
    private static readonly string[] AddedProperties = { "ComputerName", "InstanceName", "SqlInstance", "FullName", "RemoteFullName" };

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
    /// to be executed against multiple SQL Server instances.
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

    /// <para>
    /// Specifies which audit objects to retrieve by name. Accepts multiple audit names to return only those specific audits.
    /// Use this when you need to check configuration or status for particular audits instead of retrieving all instance-level audits.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Audit { get; set; }

    /// <para>
    /// Specifies which audit objects to exclude from results by name. Accepts multiple audit names to filter out unwanted audits.
    /// Use this when you want to retrieve most audits but skip specific ones, such as excluding test or temporary audits from compliance reports.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ExcludeAudit { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10 }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-refusal: Azure SQL Database has no server audits, where the pin answers it with no row and
            // no word, as for an instance with none; it is refused as -AzureUnsupported does (fleet.md step 4).
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 10, azureUnsupported: true);
            if (server is null)
            {
                continue;
            }

            // PS: $audits = $server.Audits, then each Where-Object filter and the foreach enumerate it. While $audits still
            // holds the collection (no filter ran, or the filter statement failed), each of those statements reads it again.
            List<SmoAudit>? audits = null;
            if (TestBound(nameof(Audit)))
            {
                // PS: $audits = $audits | Where-Object Name -in $Audit
                List<SmoAudit>? all = ReadAudits(server, audits);
                if (all is not null)
                {
                    audits = all.FindAll(audit => NameIn(audit.Name, Audit));
                }
            }

            if (TestBound(nameof(ExcludeAudit)))
            {
                // PS: $audits = $audits | Where-Object Name -notin $ExcludeAudit
                List<SmoAudit>? all = ReadAudits(server, audits);
                if (all is not null)
                {
                    audits = all.FindAll(audit => !NameIn(audit.Name, ExcludeAudit));
                }
            }

            // PS: foreach ($currentaudit in $audits)
            List<SmoAudit>? selected = ReadAudits(server, audits);
            if (selected is null)
            {
                continue;
            }

            foreach (SmoAudit currentAudit in selected)
            {
                WriteAudit(currentAudit);
            }
        }
    }

    // The statement's read of $audits: the filtered list once a filter has run, else the instance's collection, enumerated
    // as the engine enumerates it. A failed enumeration is the engine's statement fault; the pin writes it and goes on to
    // the next statement.
    private List<SmoAudit>? ReadAudits(Server server, List<SmoAudit>? current)
    {
        if (current is not null)
        {
            return current;
        }

        List<SmoAudit> audits = new();
        IEnumerator? enumerator = null;
        ErrorRecord fault;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(server.Audits);
            while (enumerator is not null && enumerator.MoveNext())
            {
                audits.Add((SmoAudit)enumerator.Current);
            }

            return audits;
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

    // PS: the foreach body - the two derived paths, Add-Member -Force of five note properties, then Select-DefaultView.
    private void WriteAudit(SmoAudit currentAudit)
    {
        Server parent = currentAudit.Parent;
        string computerName = SmoServerExtensions.GetComputerName(parent);

        // PS: $directory = $currentaudit.FilePath.TrimEnd("\"); $fullname = "$directory\$filename"
        //     $remote = "\\$($currentaudit.Parent.ComputerName)\" + $fullname.Replace(":", "$")
        string directory = (currentAudit.FilePath ?? string.Empty).TrimEnd('\\');
        string fullName = directory + "\\" + currentAudit.FileName;
        string remoteFullName = "\\\\" + computerName + "\\" + fullName.Replace(":", "$");

        PSObject output = PSObject.AsPSObject(currentAudit);
        foreach (string property in AddedProperties)
        {
            output.Properties.Remove(property);
        }

        OutputHelper.AddInstanceProperties(output, parent);
        output.Properties.Add(new PSNoteProperty("FullName", fullName));
        output.Properties.Add(new PSNoteProperty("RemoteFullName", remoteFullName));

        // Select-DefaultView 'Enabled as IsEnabled': Add-Member -Force -MemberType AliasProperty.
        output.Properties.Remove("IsEnabled");
        OutputHelper.AddAliasProperty(output, "IsEnabled", "Enabled");
        OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
        WriteObject(output);
    }
}
