#nullable enable

using System;
using System.IO;
using System.Management.Automation;
using System.Runtime.InteropServices;
using Dataplat.Dbatools.dbaSystem;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using DmfPolicyStore = Microsoft.SqlServer.Management.Dmf.PolicyStore;
using SqlStoreConnection = Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves the Policy-Based Management store object from SQL Server instances.
/// </summary>
/// <para>
/// Retrieves the Policy-Based Management (PBM) store object, which serves as the foundation for managing SQL Server policies, conditions, and categories. This store object is required for accessing and manipulating Policy-Based Management components programmatically. The function connects to the DMF (Declarative Management Framework) policy store and returns it with additional instance identification properties for easier scripting and automation.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPbmStore -SqlInstance sql2016
/// </code>
/// <para>
/// Return the policy store from the sql2016 instance
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaPbmStore -SqlInstance sql2016 -SqlCredential $cred
/// </code>
/// <para>
/// Uses a credential $cred to connect and return the policy store from the sql2016 instance
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Policy, PolicyBasedManagement, PBM
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
/// <seealso href="https://dbatools.io/Get-DbaPbmStore" />
// No [OutputType]: the emitted DMF PolicyStore type ships in assemblies that Add-PbmLibrary loads at run time, and the
// pinned function declares none.
[Cmdlet(VerbsCommon.Get, "DbaPbmStore")]
public sealed class GetDbaPbmStoreCommand : DbaInstanceCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
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

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    // PS: Select-DefaultView -InputObject $store -ExcludeProperty ...
    private static readonly string[] ExcludedView =
    {
        "SqlStoreConnection", "ConnectionContext", "Properties", "Urn", "Parent", "DomainInstanceName", "Metadata", "IdentityKey", "Name"
    };

    // PS: begin { Add-PbmLibrary }
    protected override void BeginProcessing()
    {
        AddPbmLibrary();
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        // PS: if ($IsLinux -or $IsMacOS) { Stop-Function -Message "This command is not supported on Linux or macOS"; return }
        // Stop-Function without -Continue sets the function's interrupt flag, so later pipeline records return at once.
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux) || RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            StopFunction("This command is not supported on Linux or macOS");
            return;
        }

        foreach (DbaInstanceParameter? instance in SqlInstance)
        {
            // The mandatory -SqlInstance binder refuses a null element before the command runs, as it does for the pin.
            if (instance is null)
                continue;

            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10 ... }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // The shared ConnectInstance runs that Stop-Function, with the one warning line naming the server for a failed
            // connection (harness-edits.md, "Script-scope preferences and the one-line connect warning", point 5).
            // Correction azure-unsupported: Policy-Based Management keeps its store in msdb, which Azure SQL Database does
            // not have, so the store refuses it as Connect-DbaInstance -AzureUnsupported does.
            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 10, azureUnsupported: true);
            if (server is null)
                continue;

            PSObject store;
            try
            {
                // PS: New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $server.ConnectionContext.SqlConnectionObject
                //     New-Object Microsoft.SqlServer.Management.DMF.PolicyStore $sqlStoreConnection
                store = NewStore(server);
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // PS: Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                ErrorRecord record = new ErrorRecord(failure, "dbatools_Get-DbaPbmStore", ErrorCategory.ConnectionError, instance);
                StopFunction("Failure", target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            // PS: Add-Member -Force ComputerName ($server.ComputerName), InstanceName ($server.ServiceName),
            // SqlInstance ($server.DomainInstanceName)
            OutputHelper.AddInstanceProperties(store, server);
            OutputHelper.SetDefaultDisplayPropertySetExcluding(store, ExcludedView);
            WriteObject(store);
        }
    }

    // Its own method, so the DMF types bind only after Add-PbmLibrary has loaded them.
    private static PSObject NewStore(Server server)
    {
        return PSObject.AsPSObject(new DmfPolicyStore(new SqlStoreConnection(server.ConnectionContext.SqlConnectionObject)));
    }

    // Add-PbmLibrary: loads the DMF assemblies from the library's lib folder. Its Stop-Function runs in the helper's own
    // scope without -EnableException, so a failure warns and does not stop this command.
    private void AddPbmLibrary()
    {
        try
        {
            string libraryLib = Path.GetDirectoryName(typeof(DmfLibrary).Assembly.Location) ?? "";
            DmfLibrary.Load(Path.GetDirectoryName(libraryLib) ?? "");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WriteAttributedMessage("Add-PbmLibrary", MessageLevel.Warning, "Could not load DMF libraries", exception: failure);
        }
    }
}
