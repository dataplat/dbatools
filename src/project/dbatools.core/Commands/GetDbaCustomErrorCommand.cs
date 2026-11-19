#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaCustomError.ps1 at refs/pins/dbatools-2026-10-22: the connect and the decorated
// $server.UserDefinedMessages with their default view.
/// <summary>Retrieves user-defined error messages from SQL Server instances for auditing and documentation.</summary>
/// <para>
/// Retrieves all custom error messages that have been added to SQL Server using sp_addmessage or through SQL Server Management Studio. These user-defined error messages are stored in the sys.messages system catalog and are commonly used by applications for business logic validation and custom error handling. This function helps DBAs inventory custom errors across multiple instances during migrations, troubleshooting, or compliance audits.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCustomError -SqlInstance localhost
/// </code>
/// <para>
/// Returns all Custom Error Message(s) on the local default SQL Server instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCustomError -SqlInstance localhost, sql2016
/// </code>
/// <para>
/// Returns all Custom Error Message(s) for the local and sql2016 SQL Server instances
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: General, Error
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
/// <seealso href="https://dbatools.io/Get-DbaCustomError" />
[Cmdlet(VerbsCommon.Get, "DbaCustomError")]
[OutputType(typeof(UserDefinedMessage))]
public sealed class GetDbaCustomErrorCommand : DbaInstanceCmdlet
{
    // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, ID, Text, LanguageID, Language
    private static readonly string[] DisplaySet = { "ComputerName", "InstanceName", "SqlInstance", "ID", "Text", "LanguageID", "Language" };

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
    /// to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
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
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-unsupported: user-defined messages do not exist in Azure SQL Database, so the connect
            // refuses it as Connect-DbaInstance -AzureUnsupported does.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            foreach (UserDefinedMessage customError in ReadMessages(server))
            {
                // PS: Add-Member -Force ComputerName, InstanceName, SqlInstance from $customError.Parent, then
                // Select-DefaultView. -Force replaces the members an earlier call left on the same SMO object.
                PSObject output = PSObject.AsPSObject(customError);
                foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance" })
                    output.Properties.Remove(property);
                OutputHelper.AddInstanceProperties(output, customError.Parent);
                OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
                WriteObject(output);
            }
        }
    }

    // PS: foreach ($customError in $server.UserDefinedMessages)
    private List<UserDefinedMessage> ReadMessages(Server server)
    {
        List<UserDefinedMessage> messages = new List<UserDefinedMessage>();
        UserDefinedMessageCollection collection = server.UserDefinedMessages;
        try
        {
            foreach (UserDefinedMessage message in collection)
                messages.Add(message);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS enumerating the collection reports a GetEnumerator failure as an ExtendedTypeSystemException with this
            // message. No target: a target that is the failing collection fails again wherever the record is rendered.
            ErrorRecord record = failure is IContainsErrorRecord container && container.ErrorRecord is not null
                ? new ErrorRecord(container.ErrorRecord, failure)
                : new ErrorRecord(new ExtendedTypeSystemException(String.Format(CultureInfo.InvariantCulture,
                    "The following exception occurred while trying to enumerate the collection: \"{0}\".", failure.Message), failure),
                    "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null);
            // caller-try: terminate -- the pinned enumeration fault is statement-terminating; the default rule terminates
            ThrowTerminatingError(record); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
        }
        return messages;
    }
}
