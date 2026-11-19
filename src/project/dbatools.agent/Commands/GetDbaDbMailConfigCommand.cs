#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Mail;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbMailConfig.ps1 at refs/pins/dbatools-2026-10-22: the nested Get-DbaDbMail read of the named
// instances, the -Name filter, and the instance columns on each configuration value.
/// <summary>Retrieves Database Mail configuration settings from SQL Server instances</summary>
/// <para>
/// Retrieves all Database Mail configuration values from SQL Server, including settings like MaxFileSize, ProhibitedExtensions, DatabaseMailExeMinLifeTime, and LoggingLevel.
/// This function helps DBAs audit current Database Mail configurations, troubleshoot email delivery issues, and verify compliance with organizational email policies.
/// You can retrieve all configuration settings or filter by specific configuration names to focus on particular settings.
/// The output includes the configuration name, current value, and description for each setting across your SQL Server environment.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMailConfig -SqlInstance sql01\sharepoint
/// </code>
/// <para>
/// Returns DBMail configs on sql01\sharepoint
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMailConfig -SqlInstance sql01\sharepoint -Name ProhibitedExtensions
/// </code>
/// <para>
/// Returns the ProhibitedExtensions configuration on sql01\sharepoint
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMailConfig -SqlInstance sql01\sharepoint | Select-Object *
/// </code>
/// <para>
/// Returns the DBMail configs on sql01\sharepoint then return a bunch more columns
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
/// PS C:\&gt; $servers | Get-DbaDbMail | Get-DbaDbMailConfig
/// </code>
/// <para>
/// Returns the DBMail configs for "sql2014","sql2016" and "sqlcluster\sharepoint"
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
/// <seealso href="https://dbatools.io/Get-DbaDbMailConfig" />
[Cmdlet(VerbsCommon.Get, "DbaDbMailConfig")]
[OutputType(typeof(ConfigurationValue))]
public sealed class GetDbaDbMailConfigCommand : DbMailCmdlet
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
    /// Specifies which Database Mail configuration settings to retrieve by name, such as MaxFileSize, ProhibitedExtensions, or LoggingLevel.
    /// Use this when you need to check specific configuration values instead of retrieving all Database Mail settings.
    /// Accepts multiple configuration names and supports aliases Config and ConfigName.
    /// </para>
    [Parameter(Position = 2)]
    [Alias("Config", "ConfigName")]
    [PsStringArrayCast]
    public string[]? Name { get; set; }

    /// <para>
    /// Accepts Database Mail objects from Get-DbaDbMail for pipeline processing.
    /// Use this when chaining multiple Database Mail functions together or when you already have Database Mail objects loaded.
    /// Allows you to retrieve configurations from multiple SQL Server instances efficiently through the pipeline.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 3)]
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

    /// <summary>Reports the configuration values of this record's mail objects and of the named instances.</summary>
    protected override void ProcessRecord()
    {
        List<SqlMail?> mailServers = new(InputObject ?? Array.Empty<SqlMail>());

        // Correction named-instance-repeat: process runs per piped record, and the named instances are read with the first.
        bool namedInstances = LanguagePrimitives.IsTrue(SqlInstance);
        bool readEarlier = namedInstances && _namedInstancesRead;
        if (namedInstances && !readEarlier)
        {
            _namedInstancesRead = true;
            AddNamedInstances(SqlInstance!, SqlCredential, mailServers, ReportNestedBindingFault);
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
            try
            {
                if (mailserver is null)
                    WriteNullMailFaults();
                else
                    WriteConfigurations(mailserver);
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                StopFunction("Failure", errorRecord: new ErrorRecord(failure, "dbatools_Get-DbaDbMailConfig", ErrorCategory.NotSpecified, null), continueLoop: true);
            }
        }
    }

    private void WriteConfigurations(SqlMail mailserver)
    {
        // PS: $configs | Add-Member walks the whole collection before the first value leaves, so a failed read gives no part of it.
        bool filtered = LanguagePrimitives.IsTrue(Name);
        List<ConfigurationValue> configs = new();
        foreach (ConfigurationValue config in mailserver.ConfigurationValues)
        {
            if (!filtered || Array.Exists(Name!, name => LanguagePrimitives.Equals(config.Name, name, true, CultureInfo.InvariantCulture)))
                configs.Add(config);
        }

        // Correction raw-mail-instance-columns: a mail object that did not come through Get-DbaDbMail has no notes, and its server knows the values.
        Server server = mailserver.Parent;
        object? computerName = SmoServerExtensions.GetPSProperty(mailserver, "ComputerName") ?? SmoServerExtensions.GetComputerName(server);
        object? instanceName = SmoServerExtensions.GetPSProperty(mailserver, "InstanceName") ?? server.ServiceName;
        object? sqlInstance = SmoServerExtensions.GetPSProperty(mailserver, "SqlInstance") ?? SmoServerExtensions.GetDomainInstanceName(server);
        foreach (ConfigurationValue config in configs)
        {
            PSObject output = PSObject.AsPSObject(config);
            RemoveProperties(output, "ComputerName", "InstanceName", "SqlInstance");
            output.Properties.Add(new PSNoteProperty("ComputerName", computerName)); // style-ok: cs-output-props the pin copies these from the mail object, which is not a Server
            output.Properties.Add(new PSNoteProperty("InstanceName", instanceName)); // style-ok: cs-output-props the pin copies these from the mail object, which is not a Server
            output.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance)); // style-ok: cs-output-props the pin copies these from the mail object, which is not a Server
            OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "InstanceName", "SqlInstance", "Name", "Value", "Description");
            WriteObject(output);
        }
    }

    // PS: Get-DbaDbMail -SqlInstance is mandatory, so the binder refuses an array holding a null before that command runs,
    // and the function resumes at its next statement.
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
            // caller-try: terminate -- -EnableException asks for the stop, and no value has left yet
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams binder fault of the nested Get-DbaDbMail, outside Stop-Function, as in the pin
        }

        // A plain call goes on, as the pin does, to "No servers to process" or to the mail objects given beside the instances;
        // under a caller try the record stops the command, as the binder fault stops the pin's statement.
        StatementFault.Surface(this, fault);
    }

    // PS: $configs | Add-Member, three times, with a null mail object and no -Name. Each fails binding on its own and the
    // function goes on, under a caller's try and -EnableException too. With -Name the filter gives Add-Member nothing to bind.
    // -ErrorAction Stop makes the first fault terminating, and the function's own catch takes it. WriteError would stop the
    // pipeline here, so the port goes to that catch's Stop-Function directly.
    private void WriteNullMailFaults()
    {
        if (LanguagePrimitives.IsTrue(Name))
            return;
        if (MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? action) && action is ActionPreference.Stop)
        {
            StopFunction("Failure", errorRecord: NewNullMailFault(), continueLoop: true);
            return;
        }
        // Not a statement-terminating fault: binding a null pipeline record writes each record and goes on, under a caller's try and -EnableException too
        // (evidence/pin-mailconfig-20261101.txt, input-two-null-elements-enable-exception), and the mail objects after it are still read.
        for (int decoration = 0; decoration < 3; decoration++)
            WriteError(NewNullMailFault());
    }

    private static ErrorRecord NewNullMailFault()
    {
        ErrorRecord fault = new(new ParameterBindingException("Cannot bind argument to parameter 'InputObject' because it is null."),
            "ParameterArgumentValidationErrorNullNotAllowed", ErrorCategory.InvalidData, null);
        fault.CategoryInfo.Reason = "ParameterBindingValidationException";
        return fault;
    }
}
