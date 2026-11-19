#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Mail;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbMailProfile.ps1 at refs/pins/dbatools-2026-10-22: the nested Get-DbaDbMail read of the named
// instances, the -Profile and -ExcludeProfile filters, and the instance and account columns on each profile.
/// <summary>Retrieves Database Mail profiles and their configuration details from SQL Server instances</summary>
/// <para>
/// Retrieves Database Mail profiles from one or more SQL Server instances, returning detailed configuration information for each profile including ID, name, description, and status properties. This function is essential for auditing Database Mail configurations across your environment, troubleshooting email notification issues, and documenting mail profile setups for compliance or change management. You can target specific profiles by name or exclude certain profiles from the results, making it useful for both broad configuration reviews and focused troubleshooting scenarios.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMailProfile -SqlInstance sql01\sharepoint
/// </code>
/// <para>
/// Returns DBMail profiles on sql01\sharepoint
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMailProfile -SqlInstance sql01\sharepoint -Profile 'The DBA Team'
/// </code>
/// <para>
/// Returns The DBA Team DBMail profile from sql01\sharepoint
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMailProfile -SqlInstance sql01\sharepoint | Select-Object *
/// </code>
/// <para>
/// Returns the DBMail profiles on sql01\sharepoint then return a bunch more columns
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $servers = "sql2014", "sql2016", "sqlcluster\sharepoint"
/// PS C:\&gt; $servers | Get-DbaDbMail | Get-DbaDbMailProfile
/// </code>
/// <para>
/// Returns the DBMail profiles for "sql2014", "sql2016" and "sqlcluster\sharepoint"
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $servers = "sql2014", "sql2016", "sqlcluster\sharepoint"
/// PS C:\&gt; Get-DbaDbMailProfile -SqlInstance $servers
/// </code>
/// <para>
/// Returns the DBMail profiles for "sql2014", "sql2016" and "sqlcluster\sharepoint"
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Mail, DbMail, Email
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
/// <seealso href="https://dbatools.io/Get-DbaDbMailProfile" />
[Cmdlet(VerbsCommon.Get, "DbaDbMailProfile")]
[OutputType(typeof(MailProfile))]
public sealed class GetDbaDbMailProfileCommand : DbMailCmdlet
{
    private bool _namedInstancesRead;

    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

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
    public PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies one or more Database Mail profile names to retrieve. Use this when you need to check configuration details for specific profiles rather than reviewing all profiles.
    /// Accepts exact profile names and is case-sensitive to match SQL Server Database Mail profile naming.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Profile { get; set; }

    /// <para>
    /// Specifies one or more Database Mail profile names to exclude from the results. Useful when auditing multiple profiles but want to skip certain ones like test or deprecated profiles.
    /// Helps focus on production profiles during compliance reviews or troubleshooting scenarios.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ExcludeProfile { get; set; }

    /// <para>
    /// Accepts Database Mail server objects from Get-DbaDbMail cmdlet through the pipeline. This allows you to chain commands when working with multiple SQL instances.
    /// Eliminates the need to specify SqlInstance when you already have Database Mail objects from a previous command.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    [PsDbMailArrayCast]
    public SqlMail[]? InputObject { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <summary>Reports the profiles of this record's mail objects and of the named instances.</summary>
    protected override void ProcessRecord()
    {
        List<SqlMail?> mailServers = new(InputObject ?? Array.Empty<SqlMail>());

        // Correction named-instance-repeat: process runs per piped record, and the named instances are read with the first.
        bool namedInstances = SqlInstance is { Length: > 0 };
        bool readEarlier = namedInstances && _namedInstancesRead;
        if (namedInstances && !readEarlier)
        {
            _namedInstancesRead = true;
            AddNamedInstances(mailServers);
        }

        // PS: if (-not $InputObject) reads the truthiness of the array, so one null element is no server either.
        // The function reads no stop flag: every later record still runs, and warns again when it brings nothing.
        if (!LanguagePrimitives.IsTrue(mailServers))
        {
            if (!readEarlier)
                StopFunction("No servers to process");
            return;
        }

        foreach (SqlMail? mailserver in mailServers)
        {
            // PS: a null element's .Profiles is null, the filters give nothing, and foreach has nothing to walk.
            if (mailserver is null)
                continue;

            try
            {
                WriteProfiles(mailserver);
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                StopFunction("Failure", errorRecord: new ErrorRecord(failure, "dbatools_Get-DbaDbMailProfile", ErrorCategory.NotSpecified, null), continueLoop: true);
            }
        }
    }

    // PS: foreach ($instance in $SqlInstance) { $InputObject += Get-DbaDbMail -SqlInstance $instance -SqlCredential $SqlCredential }.
    // One nested call per element, so a null element is one binder fault and the elements beside it are still read.
    // -EnableException never reaches that call, so its Stop-Function warns under its own name.
    private void AddNamedInstances(List<SqlMail?> mailServers)
    {
        foreach (DbaInstanceParameter? instance in SqlInstance!)
        {
            if (instance is null)
            {
                ReportNestedBindingFault();
                continue;
            }

            SqlMail? mail = ReadMail(instance, SqlCredential);
            if (mail is not null)
                mailServers.Add(mail);
        }
    }

    private void WriteProfiles(SqlMail mailserver)
    {
        bool included = LanguagePrimitives.IsTrue(Profile);
        bool excluded = LanguagePrimitives.IsTrue(ExcludeProfile);

        // Correction raw-mail-instance-columns: a mail object that did not come through Get-DbaDbMail has no notes, and its server knows the values.
        Server server = mailserver.Parent;
        object? computerName = SmoServerExtensions.GetPSProperty(mailserver, "ComputerName") ?? SmoServerExtensions.GetComputerName(server);
        object? instanceName = SmoServerExtensions.GetPSProperty(mailserver, "InstanceName") ?? server.ServiceName;
        object? sqlInstance = SmoServerExtensions.GetPSProperty(mailserver, "SqlInstance") ?? SmoServerExtensions.GetDomainInstanceName(server);

        foreach (MailProfile prof in mailserver.Profiles)
        {
            if (included && !IsNamed(Profile!, prof.Name))
                continue;
            if (excluded && IsNamed(ExcludeProfile!, prof.Name))
                continue;

            PSObject output = PSObject.AsPSObject(prof);
            RemoveProperties(output, "ComputerName", "InstanceName", "SqlInstance", "MailAccount");
            output.Properties.Add(new PSNoteProperty("ComputerName", computerName)); // style-ok: cs-output-props the pin copies these from the mail object, which is not a Server
            output.Properties.Add(new PSNoteProperty("InstanceName", instanceName)); // style-ok: cs-output-props the pin copies these from the mail object, which is not a Server
            output.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance)); // style-ok: cs-output-props the pin copies these from the mail object, which is not a Server
            output.Properties.Add(new PSNoteProperty("MailAccount", ReadAccountNames(prof)));
            OutputHelper.SetDefaultDisplayPropertySet(output,
                "ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "Description",
                "ForceDeleteForActiveProfiles", "IsBusyProfile", "MailAccount");
            WriteObject(output);
        }
    }

    // PS: $prof.EnumAccounts().AccountName walks the rows: no value without an account, the bare value with one, an array with more.
    private static object? ReadAccountNames(MailProfile prof)
    {
        List<object> names = new();
        foreach (DataRow row in prof.EnumAccounts().Rows)
            names.Add(row["AccountName"]);

        return names.Count switch
        {
            0 => null,
            1 => names[0],
            _ => names.ToArray()
        };
    }

    // PS: Where-Object Name -In and -NotIn compare whole names without regard to case.
    private static bool IsNamed(string[] names, string profileName) =>
        Array.Exists(names, name => LanguagePrimitives.Equals(profileName, name, true, CultureInfo.InvariantCulture));

    // PS: Get-DbaDbMail -SqlInstance is mandatory, so the binder refuses a null instance before that command runs. The
    // fault ends one statement of the loop, and a plain call reads the other instances.
    private void ReportNestedBindingFault()
    {
        ErrorRecord fault = new(new ParameterBindingException("Cannot bind argument to parameter 'SqlInstance' because it is null."),
            "ParameterArgumentValidationErrorNullNotAllowed", ErrorCategory.InvalidData, null);
        // The binder's own exception type is internal, so the record carries its public base and the Reason callers read.
        fault.CategoryInfo.Reason = "ParameterBindingValidationException";
        // The pin's activity follows its id suffix: the nested command when the caller has no try and the call has no -ErrorAction Stop. Under a
        // caller's try or that switch the fault leaves through this command, and the engine's default activity, this cmdlet's name, is already the pin's.
        bool stopAsked = MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? errorAction)
            && String.Equals(LanguagePrimitives.ConvertTo<string>(errorAction), "Stop", StringComparison.OrdinalIgnoreCase);
        if (!stopAsked && !StatementFault.CallerHasEnclosingTry(this))
            fault.CategoryInfo.Activity = "Get-DbaDbMail";

        // Differences from the pin's flow with no caller try, kept by the binder section's point 2 and the keep-going section's point 3. -EnableException stops
        // here with this record; the pin writes it and goes on. -ErrorAction Stop has the effect PowerShell gives WriteError, which ends the script; the pin writes
        // the record and runs the next statement. $ErrorActionPreference set in the caller's scope or at a script's top acts on this WriteError as for any compiled
        // command, where the pin ignores it: harness-edits.md, "Script-scope preferences and the one-line connect warning", points 1 and 2.
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop, and no row has left yet
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams binder fault of the nested Get-DbaDbMail, outside Stop-Function, as in the pin
        }

        // A plain call goes on, as the pin does, to the other instances and the mail objects given beside them; under a caller
        // try the record stops the command, as the binder fault stops the pin's statement.
        StatementFault.Surface(this, fault);
    }
}
