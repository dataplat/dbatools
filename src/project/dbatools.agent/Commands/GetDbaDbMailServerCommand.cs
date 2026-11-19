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

// Port of public/Get-DbaDbMailServer.ps1 at refs/pins/dbatools-2026-10-22: the nested Get-DbaDbMail read of the named
// instances, the nested Get-DbaDbMailAccount read of each mail object, the -Server filter, and the instance and account
// columns on each mail server.
/// <summary>Retrieves SMTP server configurations from SQL Server Database Mail accounts</summary>
/// <para>
/// Retrieves detailed SMTP server configuration information from all Database Mail accounts on SQL Server instances. This function pulls the actual mail server settings including port numbers, SSL configuration, authentication methods, and connection details. Useful for auditing email infrastructure, troubleshooting delivery issues, and documenting Database Mail configurations across your environment.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMailServer -SqlInstance sql01\sharepoint
/// </code>
/// <para>
/// Returns all DBMail servers on sql01\sharepoint
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMailServer -SqlInstance sql01\sharepoint -Server DbaTeam
/// </code>
/// <para>
/// Returns The DBA Team DBMail server from sql01\sharepoint
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbMailServer -SqlInstance sql01\sharepoint | Select-Object *
/// </code>
/// <para>
/// Returns the DBMail servers on sql01\sharepoint then return a bunch more columns
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
/// PS C:\&gt; $servers | Get-DbaDbMail | Get-DbaDbMailServer
/// </code>
/// <para>
/// Returns the DBMail servers for "sql2014","sql2016" and "sqlcluster\sharepoint"
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
/// <seealso href="https://dbatools.io/Get-DbaDbMailServer" />
[Cmdlet(VerbsCommon.Get, "DbaDbMailServer")]
[OutputType(typeof(MailServer))]
public sealed class GetDbaDbMailServerCommand : DbMailCmdlet
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
    /// Specifies one or more SMTP server names to retrieve from Database Mail accounts. Use this when you need to check configuration for specific mail servers rather than all configured servers.
    /// Accepts exact server names like 'smtp.company.com' or 'mail-relay-01'.
    /// </para>
    [Parameter(Position = 2)]
    [Alias("Name")]
    [PsStringArrayCast]
    public string[]? Server { get; set; }

    /// <para>
    /// Restricts results to mail servers associated with specific Database Mail account names. Use this when troubleshooting email issues for particular applications or services.
    /// Helpful for isolating server configurations when you have multiple Database Mail accounts with different SMTP settings.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Account { get; set; }

    /// <para>
    /// Accepts Database Mail objects from Get-DbaDbMail via pipeline. Allows you to chain Database Mail operations together.
    /// Use this when you need to process mail server configurations from a filtered set of SQL instances or specific Database Mail setups.
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

    /// <summary>Reports the mail servers of this record's mail objects and of the named instances.</summary>
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
                WriteMailServers(mailserver, ReadAccounts(mailserver));
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                StopFunction("Failure", errorRecord: new ErrorRecord(failure, "dbatools_Get-DbaDbMailServer", ErrorCategory.NotSpecified, null), continueLoop: true);
            }
        }
    }

    // PS: $mailserver | Get-DbaDbMailAccount -Account $Account. -EnableException never reaches that call either, and its own
    // catch keeps the accounts that left before a failure.
    private List<MailAccount> ReadAccounts(SqlMail? mailserver)
    {
        List<MailAccount> accounts = new();
        if (mailserver is null)
        {
            WarnNestedStopFunction("Get-DbaDbMailAccount", "No servers to process");
            return accounts;
        }

        try
        {
            bool filtered = LanguagePrimitives.IsTrue(Account);
            InstanceColumns columns = ReadInstanceColumns(mailserver);
            foreach (MailAccount account in SelectAccounts(mailserver, filtered))
            {
                PSObject output = PSObject.AsPSObject(account);
                RemoveProperties(output, "ComputerName", "InstanceName", "SqlInstance", "MailProfile");
                columns.AddTo(output);
                output.Properties.Add(new PSNoteProperty("MailProfile", account.GetAccountProfileNames()));
                OutputHelper.SetDefaultDisplayPropertySet(output,
                    "ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "DisplayName", "Description", "EmailAddress", "ReplyToAddress", "IsBusyAccount", "MailServers", "MailProfile");
                accounts.Add(account);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_Get-DbaDbMailAccount", ErrorCategory.NotSpecified, null);
            WarnNestedStopFunction("Get-DbaDbMailAccount", "Failure", null, record);
        }
        return accounts;
    }

    // PS: $accounts | Where-Object Name -in $Account walks the whole collection before foreach takes the first account.
    private IEnumerable<MailAccount> SelectAccounts(SqlMail mailserver, bool filtered)
    {
        if (!filtered)
        {
            foreach (MailAccount account in mailserver.Accounts)
                yield return account;
            yield break;
        }

        List<MailAccount> selected = new();
        foreach (MailAccount account in mailserver.Accounts)
        {
            if (MatchesAny(account.Name, Account!))
                selected.Add(account);
        }
        foreach (MailAccount account in selected)
            yield return account;
    }

    private void WriteMailServers(SqlMail? mailserver, List<MailAccount> accounts)
    {
        // PS: $servers | Add-Member walks every server before the first leaves, so a failed read gives no part of it.
        bool filtered = LanguagePrimitives.IsTrue(Server);
        List<MailServer> servers = new();
        foreach (MailAccount account in accounts)
        {
            foreach (MailServer server in account.MailServers)
            {
                if (!filtered || MatchesAny(server.Name, Server!))
                    servers.Add(server);
            }
        }
        if (servers.Count == 0)
            return;

        InstanceColumns columns = ReadInstanceColumns(mailserver!);
        foreach (MailServer server in servers)
        {
            PSObject output = PSObject.AsPSObject(server);
            RemoveProperties(output, "ComputerName", "InstanceName", "SqlInstance", "Account");
            columns.AddTo(output);
            // Correction account-column: each server names its own account, where the pin gave every server all the names.
            output.Properties.Add(new PSNoteProperty("Account", server.Parent.Name));
            OutputHelper.SetDefaultDisplayPropertySet(output,
                "ComputerName", "InstanceName", "SqlInstance", "Account", "Name", "Port", "EnableSsl", "ServerType", "UserName", "UseDefaultCredentials", "NoCredentialChange");
            WriteObject(output);
        }
    }

    // PS: Where-Object Name -in $values, a whole name without regard to case.
    private static bool MatchesAny(string name, string[] values)
    {
        return Array.Exists(values, value => LanguagePrimitives.Equals(name, value, true, CultureInfo.InvariantCulture));
    }

    // Correction raw-mail-instance-columns: a mail object that did not come through Get-DbaDbMail has no notes, and its server knows the values.
    private static InstanceColumns ReadInstanceColumns(SqlMail mailserver)
    {
        Server server = mailserver.Parent;
        return new InstanceColumns(
            SmoServerExtensions.GetPSProperty(mailserver, "ComputerName") ?? SmoServerExtensions.GetComputerName(server),
            SmoServerExtensions.GetPSProperty(mailserver, "InstanceName") ?? server.ServiceName,
            SmoServerExtensions.GetPSProperty(mailserver, "SqlInstance") ?? SmoServerExtensions.GetDomainInstanceName(server));
    }

    // PS: Get-DbaDbMail -SqlInstance is mandatory, so the binder refuses an array holding a null before that command runs,
    // and the function resumes at its next statement.
    private void ReportNestedBindingFault()
    {
        ErrorRecord fault = new(new ParameterBindingException("Cannot bind argument to parameter 'SqlInstance' because it is null."),
            "ParameterArgumentValidationErrorNullNotAllowed", ErrorCategory.InvalidData, null);
        // The binder's own exception type is internal, so the record carries its public base and the Reason callers read.
        fault.CategoryInfo.Reason = "ParameterBindingValidationException";
        // The pin's activity follows its id suffix, measured on both editions: the nested command when the caller has no try and the
        // call has no -ErrorAction Stop. Under a caller's try or that switch the fault leaves through this command, and the engine's
        // default activity, this cmdlet's name, is already the pin's.
        bool stopAsked = MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? errorAction)
            && String.Equals(LanguagePrimitives.ConvertTo<string>(errorAction), "Stop", StringComparison.OrdinalIgnoreCase);
        if (!stopAsked && !StatementFault.CallerHasEnclosingTry(this))
            fault.CategoryInfo.Activity = "Get-DbaDbMail";

        // Differences from the pin's flow with no caller try, measured on both editions and kept by the binder section's point 2 and the
        // keep-going section's point 3. -EnableException stops here with this record; the pin writes it and goes on, to the mail objects
        // beside the instances and the next statement, or to its "No servers to process" stop. -ErrorAction Stop has the effect PowerShell
        // gives WriteError, which ends the script; the pin writes the record, returns no row and runs the next statement.
        // $ErrorActionPreference = "Stop" set in the caller's scope or at a script's top stops at this WriteError too, and "SilentlyContinue" there
        // silences the record, as for any compiled command; the pin ignores both there and writes the record. Accepted, with no lending of the
        // caller's preference: harness-edits.md, "Script-scope preferences and the one-line connect warning", points 1 and 2.
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop, and no server has left yet
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams binder fault of the nested Get-DbaDbMail, outside Stop-Function, as in the pin
        }

        // A plain call goes on, as the pin does, to "No servers to process" or to the mail objects given beside the
        // instances; under a caller try the record stops the command, as the binder fault stops the pin's statement.
        StatementFault.Surface(this, fault);
    }

    // The three instance columns the pin copies from the mail object, which is not a Server.
    private readonly struct InstanceColumns
    {
        private readonly object? _computerName;
        private readonly object? _instanceName;
        private readonly object? _sqlInstance;

        internal InstanceColumns(object? computerName, object? instanceName, object? sqlInstance)
        {
            _computerName = computerName;
            _instanceName = instanceName;
            _sqlInstance = sqlInstance;
        }

        internal void AddTo(PSObject output)
        {
            output.Properties.Add(new PSNoteProperty("ComputerName", _computerName)); // style-ok: cs-output-props the pin copies these from the mail object, which is not a Server
            output.Properties.Add(new PSNoteProperty("InstanceName", _instanceName)); // style-ok: cs-output-props the pin copies these from the mail object, which is not a Server
            output.Properties.Add(new PSNoteProperty("SqlInstance", _sqlInstance)); // style-ok: cs-output-props the pin copies these from the mail object, which is not a Server
        }
    }
}
