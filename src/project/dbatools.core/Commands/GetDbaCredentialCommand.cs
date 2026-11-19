#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaCredential.ps1 at refs/pins/dbatools-2026-10-22: the connect, the four name and identity
// filters over $server.Credentials and the decorated credentials with their default view.
/// <summary>Retrieves SQL Server Credentials configured for external authentication and resource access.</summary>
/// <para>
/// Retrieves SQL Server Credentials that are stored securely on the server and used by SQL Server services to authenticate to external resources like file shares, web services, or other SQL Server instances. These credentials are essential for operations like backups to network locations, accessing external data sources, or running SQL Agent jobs that interact with external systems. The function returns detailed information about each credential including its name, associated identity, and provider configuration.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCredential -SqlInstance localhost
/// </code>
/// <para>
/// Returns all SQL Credentials on the local default SQL Server instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCredential -SqlInstance localhost, sql2016 -Name 'PowerShell Proxy'
/// </code>
/// <para>
/// Returns the SQL Credentials named 'PowerShell Proxy' for the local and sql2016 SQL Server instances
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCredential -SqlInstance localhost, sql2016 -Identity ad\powershell
/// </code>
/// <para>
/// Returns the SQL Credentials for the account 'ad\powershell' on the local and sql2016 SQL Server instances
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Security, Credential
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
/// <seealso href="https://dbatools.io/Get-DbaCredential" />
[Cmdlet(VerbsCommon.Get, "DbaCredential")]
public sealed class GetDbaCredentialCommand : DbaInstanceCmdlet
{
    // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, ID, Name, Identity, MappedClassType, ProviderName
    private static readonly string[] DisplaySet = { "ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "Identity", "MappedClassType", "ProviderName" };

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
    /// Filters results to only include SQL Server credentials with specific names. Accepts multiple credential names and supports wildcards.
    /// Use this when you need to check configuration for specific credentials like backup service accounts or external data source connections.
    /// Enclose names with spaces in quotes, such as "My Backup Credential".
    /// </para>
    [Parameter(Position = 2)]
    [Alias("Name")]
    public string[]? Credential { get; set; }

    /// <para>
    /// Excludes SQL Server credentials with specified names from the results. Accepts multiple credential names to filter out.
    /// Useful when auditing all credentials except system or known service credentials that don't require review.
    /// </para>
    [Parameter(Position = 3)]
    [Alias("ExcludeName")]
    public string[]? ExcludeCredential { get; set; }

    /// <para>
    /// Filters results to only include credentials that use specific Windows identities or SQL logins. Accepts multiple identity names.
    /// Use this to find all credentials associated with a particular service account or user across different credential objects.
    /// Enclose identities with spaces in quotes, such as "DOMAIN\Service Account".
    /// </para>
    [Parameter(Position = 4)]
    [Alias("CredentialIdentity")]
    public string[]? Identity { get; set; }

    /// <para>
    /// Excludes credentials that use specified Windows identities or SQL logins from the results. Accepts multiple identity names.
    /// Helpful when auditing credentials but excluding known system accounts or service identities from the output.
    /// </para>
    [Parameter(Position = 5)]
    [Alias("ExcludeCredentialIdentity")]
    public string[]? ExcludeIdentity { get; set; }

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
            // Correction azure-unsupported: server credentials do not exist in Azure SQL Database, so the connect refuses
            // it as Connect-DbaInstance -AzureUnsupported does.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            List<Credential> credentials = ReadCredentials(server);

            // Correction recovery-filters: in the pin a filter statement whose read faulted leaves $creds as the
            // collection, so when a later read works that filter is never applied and the caller gets credentials it
            // excluded. Every active filter applies to the read that worked.
            bool useCredential = LanguagePrimitives.IsTrue(Credential);
            bool useExcludeCredential = LanguagePrimitives.IsTrue(ExcludeCredential);
            bool useIdentity = LanguagePrimitives.IsTrue(Identity);
            bool useExcludeIdentity = LanguagePrimitives.IsTrue(ExcludeIdentity);

            // Correction credential-wildcards: the help documents wildcards for -Credential, which the pinned -contains
            // never matched; the shared rule E+ matcher keeps every real name and bracketed value literal.
            WildcardNameMatcher? nameMatcher = null;
            if (useCredential)
            {
                List<string> scope = credentials.ConvertAll(cached => cached.Name);
                nameMatcher = WildcardNameFilter.CreateMatcher(Credential, true,
                    (value, name) => PsString.Eq(value as string, name), scope);
            }

            foreach (Credential credential in credentials)
            {
                // PS: $creds | Where-Object { $Credential -contains $_.Name } ... { $ExcludeIdentity -notcontains $_.Identity }
                if (nameMatcher is not null && !nameMatcher.Matches(credential.Name))
                    continue;
                if (useExcludeCredential && PsString.In(credential.Name, ExcludeCredential!))
                    continue;
                if (useIdentity && !PsString.In(credential.Identity, Identity!))
                    continue;
                if (useExcludeIdentity && PsString.In(credential.Identity, ExcludeIdentity!))
                    continue;

                // PS: Add-Member -Force ComputerName, InstanceName, SqlInstance from $currentcredential.Parent, then
                // Select-DefaultView. -Force replaces the members an earlier call left on the same SMO object.
                PSObject output = PSObject.AsPSObject(credential);
                foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance" })
                    output.Properties.Remove(property);
                OutputHelper.AddInstanceProperties(output, credential.Parent);
                OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
                WriteObject(output);
            }
        }
    }

    // PS: $creds = $server.Credentials, enumerated by each active filter and then by the foreach. A fault ends that one
    // statement, so the next one enumerates again, and after the foreach's fault the next instance is read.
    private List<Credential> ReadCredentials(Server server)
    {
        int reads = 1;
        foreach (string[]? filter in new[] { Credential, ExcludeCredential, Identity, ExcludeIdentity })
        {
            if (LanguagePrimitives.IsTrue(filter))
                reads++;
        }

        CredentialCollection collection = server.Credentials;
        for (int read = 0; read < reads; read++)
        {
            try
            {
                List<Credential> credentials = new List<Credential>();
                foreach (Credential credential in collection)
                    credentials.Add(credential);
                return credentials;
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                ReportReadFault(failure);
            }
        }
        return new List<Credential>();
    }

    private void ReportReadFault(Exception failure)
    {
        // PS enumerating the collection reports a GetEnumerator failure as an ExtendedTypeSystemException with this
        // message (evidence/pin-credential-faults-20261101.txt). No target: a target that is the failing collection
        // fails again wherever the record is rendered.
        ErrorRecord record = failure is IContainsErrorRecord container && container.ErrorRecord is not null
            ? new ErrorRecord(container.ErrorRecord, failure)
            : new ErrorRecord(new ExtendedTypeSystemException(String.Format(CultureInfo.InvariantCulture,
                "The following exception occurred while trying to enumerate the collection: \"{0}\".", failure.Message), failure),
                "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null);

        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(record); // style-ok: cs-raw-streams pinned statement fault outside Stop-Function
        }

        // A plain call goes on to the pin's next statement, and after the foreach to the next instance; under a caller
        // try the record stops the command, as the fault stops the pin's statement (pin probe cases try-*).
        StatementFault.Surface(this, record);
    }
}
