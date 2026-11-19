#nullable enable

using System;
using System.Collections;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaBackupDevice.ps1: the connect and the decorated backup devices run here in C#, streamed per
// instance as the pinned process block emits them. Correction: azure-unsupported.
/// <summary>Retrieves configured backup devices from SQL Server instances for inventory and management</summary>
/// <para>
/// This function returns all backup devices configured on SQL Server instances, including their type (disk, tape, URL), physical locations, and settings. Backup devices are logical names that map to physical backup destinations, allowing DBAs to create standardized backup locations that can be referenced in backup scripts and maintenance plans. Use this to audit backup device configurations across your environment, verify backup paths are accessible, or document your backup infrastructure for compliance and disaster recovery planning.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaBackupDevice -SqlInstance localhost
/// </code>
/// <para>
/// Returns all Backup Devices on the local default SQL Server instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaBackupDevice -SqlInstance localhost, sql2016
/// </code>
/// <para>
/// Returns all Backup Devices for the local and sql2016 SQL Server instances
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Backup, General
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
/// <seealso href="https://dbatools.io/Get-DbaBackupDevice" />
[Cmdlet(VerbsCommon.Get, "DbaBackupDevice")]
public sealed class GetDbaBackupDeviceCommand : DbaInstanceCmdlet
{
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
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-unsupported: Azure SQL Database has no backup devices (backup and restore syntax is not
            // supported there), so it is refused as Connect-DbaInstance -AzureUnsupported does.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            // PS: foreach ($backupDevice in $server.BackupDevices) { Add-Member ...; Select-DefaultView ... }
            IEnumerator? enumerator = null;
            try
            {
                BackupDeviceCollection devices = server.BackupDevices;
                enumerator = LanguagePrimitives.GetEnumerator(devices);
                while (enumerator is not null && enumerator.MoveNext())
                {
                    if (enumerator.Current is BackupDevice backupDevice)
                        WriteObject(Decorate(server, backupDevice));
                }
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                ErrorRecord record = EnumerationFaultRecord(failure, enumerator);
                // The pin's raw fault does not stop under -EnableException (item probe backupdevice-read-fault-20261117); the
                // port does ("Operator decision: keep going unless -EnableException (2026-11-01)", point 3).
                if (EnableException)
                    // caller-try: terminate -- -EnableException stops the command at the BackupDevices read fault.
                    ThrowTerminatingError(record); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
                // Under -ErrorAction Stop with no caller try, the pin's raw fault ends only its pipeline statement: the record
                // reaches the error stream and the caller's next statement runs. WriteError under Stop would end the caller's
                // whole script instead, so the port ends the command here (route (B), watchman audit 58a366d9).
                bool stopAsked = MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? errorAction)
                    && String.Equals(LanguagePrimitives.ConvertTo<string>(errorAction), "Stop", StringComparison.OrdinalIgnoreCase);
                if (stopAsked && !StatementFault.CallerHasEnclosingTry(this))
                    // caller-try: terminate -- -ErrorAction Stop outside a caller try ends only this statement, as the pin's raw fault does (route (B), 58a366d9)
                    ThrowTerminatingError(record); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
                // PS: foreach ($backupDevice in $server.BackupDevices) faults as a statement: a plain call writes the record and
                // goes on with the next instance, and inside a caller's try or trap the fault ends the command; Surface does
                // both. The devices read before the fault are already streamed, so nothing stale or wrong is emitted.
                StatementFault.Surface(this, record);
            }
        }
    }

    // PS: Add-Member ComputerName, InstanceName, SqlInstance from $backupDevice.Parent; Select-DefaultView.
    private static PSObject Decorate(Server server, BackupDevice backupDevice)
    {
        PSObject wrapped = PSObject.AsPSObject(backupDevice);
        ReplaceNoteProperty(wrapped, "ComputerName", SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", SmoServerExtensions.GetDomainInstanceName(server));
        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "Name", "BackupDeviceType", "PhysicalLocation", "SkipTapeLabel");
        return wrapped;
    }

    // The engine's record when the failure carries one (a getter or GetEnumerator fault); otherwise the record a failing
    // MoveNext gives (BadEnumeration, InvalidOperation, the enumerator as target).
    private static ErrorRecord EnumerationFaultRecord(Exception failure, IEnumerator? enumerator)
    {
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            return new ErrorRecord(container.ErrorRecord, failure);
        if (enumerator is null)
        {
            GetValueInvocationException getter = new(String.Format(CultureInfo.InvariantCulture,
                "Exception getting \"BackupDevices\": \"{0}\"", failure.Message), failure);
            return new ErrorRecord(getter, "ExceptionWhenGetting", ErrorCategory.NotSpecified, null);
        }
        RuntimeException fault = new(String.Format(CultureInfo.InvariantCulture,
            "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
        return new ErrorRecord(fault, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
    }

    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        if (wrapped.Properties[name] is PSNoteProperty)
            wrapped.Properties.Remove(name);
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }
}
