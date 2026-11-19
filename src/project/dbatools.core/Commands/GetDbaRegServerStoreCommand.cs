#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;
using System.Reflection;
using Dataplat.Dbatools.dbaSystem;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.RegisteredServers;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaRegServerStore.ps1 at refs/pins/dbatools-2026-10-22. Per instance: the connect with
// -IsNewConnectionReference, the RegisteredServersStore on its ConnectionContext, the five added members and the
// Select-DefaultView -ExcludeProperty view. With no -SqlInstance value, the local file store: RegSrvr.xml copied from the
// module's bin folder when the user's file is missing, then RegisteredServersStore.InitChildObjects on that file through
// reflection, as the pin calls it.
/// <summary>Creates a RegisteredServersStore object for managing Central Management Server configurations</summary>
/// <para>
/// Creates a RegisteredServersStore object that serves as the foundation for working with SQL Server Central Management Server (CMS). This object provides access to server groups and registered servers stored in the CMS repository, allowing you to programmatically manage multiple SQL Server instances from a centralized location. When no SqlInstance is specified, it returns the local file store which contains your locally registered servers from SQL Server Management Studio. The returned object can be used with other dbatools CMS commands like Get-DbaRegServer and Get-DbaRegServerGroup to retrieve and manage your registered server configurations.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRegServerStore -SqlInstance sqlserver2014a
/// </code>
/// <para>
/// Returns a SQL Server Registered Server Store Object from sqlserver2014a
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaRegServerStore -SqlInstance sqlserver2014a -SqlCredential sqladmin
/// </code>
/// <para>
/// Returns a SQL Server Registered Server Store Object from sqlserver2014a  by logging in with the sqladmin login
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: RegisteredServer,CMS
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
/// <seealso href="https://dbatools.io/Get-DbaRegServerStore" />
[Cmdlet(VerbsCommon.Get, "DbaRegServerStore")]
public sealed class GetDbaRegServerStoreCommand : DbaInstanceCmdlet
{
    /// <para>
    /// Specifies the SQL Server instance hosting the Central Management Server to retrieve the registered server store from.
    /// When omitted, returns the local file store containing your locally registered servers from SQL Server Management Studio.
    /// Use this when you need to access server groups and registered servers stored in a centralized CMS repository.
    /// </para>
    [Parameter(Position = 0, ValueFromPipeline = true)]
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
        "ServerConnection", "DomainInstanceName", "DomainName", "Urn", "Properties", "Metadata", "Parent", "ConnectionContext",
        "PropertyMetadataChanged", "PropertyChanged", "ParentServer", "IsNewConnection",
    };

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter? instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            // PS: foreach over a [DbaInstanceParameter[]] holding $null gives Connect-DbaInstance a null -SqlInstance, which
            // its binder refuses; the shared connect refuses the null target the same way, with the Stop-Function below.
            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -IsNewConnectionReference ([ref]$isNewConnection) }
            //     catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-unsupported: a Central Management Server keeps its groups in msdb, which Azure SQL Database
            // does not have, so the store refuses it as Connect-DbaInstance -AzureUnsupported does.
            Server? server = ConnectInstance(instance!, out bool isNewConnection, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            PSObject store;
            try
            {
                // PS: $store = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($server.ConnectionContext)
                store = PSObject.AsPSObject(new RegisteredServersStore(server.ConnectionContext));
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // PS: catch { Stop-Function -Message "Cannot access Central Management Server on $instance" -Category ConnectionError
                //     -ErrorRecord $_ -Target $instance -Continue }. $_ is New-Object's record of the failed constructor call.
                ErrorRecord record = ConstructorFaultRecord(failure, instance);
                StopFunction(String.Format(CultureInfo.InvariantCulture, "Cannot access Central Management Server on {0}", instance),
                    target: instance, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            // PS: Add-Member -Force ComputerName ($server.ComputerName), InstanceName ($server.ServiceName),
            // SqlInstance ($server.DomainInstanceName), ParentServer ($server), IsNewConnection ($isNewConnection)
            OutputHelper.AddInstanceProperties(store, server);
            store.Properties.Add(new PSNoteProperty("ParentServer", server));
            store.Properties.Add(new PSNoteProperty("IsNewConnection", isNewConnection));
            OutputHelper.SetDefaultDisplayPropertySetExcluding(store, ExcludedView);
            WriteObject(store);
        }

        // PS: if (-not $PSBoundParameters.SqlInstance): the bound value's truthiness, so an unbound, null or empty
        // -SqlInstance reads the local file store too.
        if (!LanguagePrimitives.IsTrue(TestBound(nameof(SqlInstance)) ? SqlInstance : null))
        {
            object? localStore = ReadLocalStore(this, SurfaceFault);
            if (localStore is not null)
                WriteObject(localStore);
        }
    }

    // The record New-Object gives the failed RegisteredServersStore constructor call, the $_ of the pin's
    // "Cannot access Central Management Server on $instance" Stop-Function. Get-DbaRegServerGroup's nested call shares it.
    internal static ErrorRecord ConstructorFaultRecord(Exception failure, object? instance)
    {
        MethodInvocationException constructorFault = new(MethodFault(".ctor", 1, failure), failure);
        return new ErrorRecord(constructorFault, "dbatools_Get-DbaRegServerStore", ErrorCategory.ConnectionError, instance);
    }

    // PS: $file = [RegisteredServersStore]::LocalFileStore.DomainInstanceName; if ($file) { if (-not (Test-Path -Path $file)) {
    //     Copy-Item -Path (Join-DbaPath $script:PSModuleRoot bin, RegSrvr.xml) -Destination $file -Force }
    //     $initMethod = [RegisteredServersStore].GetMethod('InitChildObjects', 'Static,NonPublic'); $initMethod.Invoke($null, @($file)) }
    // Returns the local store, the command's output, or null. Each statement fault goes to surfaceFault, the calling
    // command's StatementFault.Surface site; Get-DbaRegServerGroup's nested call shares this reader.
    internal static object? ReadLocalStore(PSCmdlet cmdlet, Action<ErrorRecord> surfaceFault)
    {
        string? file;
        try
        {
            file = RegisteredServersStore.LocalFileStore.DomainInstanceName;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // The pin's assignment fails as a statement and $file stays unset, so nothing more is done.
            surfaceFault(new ErrorRecord(new GetValueInvocationException(String.Format(CultureInfo.InvariantCulture,
                "Exception getting \"LocalFileStore\": \"{0}\"", failure.Message), failure), "ExceptionWhenGetting", ErrorCategory.NotSpecified, null));
            return null;
        }

        if (String.IsNullOrEmpty(file))
            return null;

        if (!TestPath(cmdlet, file!))
            CopyTemplateStore(cmdlet, file!);

        // PS: $initMethod.Invoke($null, @($file)): its result, the local store, is the command's output.
        MethodInfo? initMethod = typeof(RegisteredServersStore).GetMethod("InitChildObjects", BindingFlags.Static | BindingFlags.NonPublic);
        if (initMethod is null)
        {
            surfaceFault(new ErrorRecord(new RuntimeException("You cannot call a method on a null-valued expression."), "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null));
            return null;
        }

        object? localStore;
        try
        {
            localStore = initMethod.Invoke(null, new object?[] { file });
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PowerShell reports the exception InitChildObjects threw, not the reflection wrapper around it: the record's id is
            // its type name and the method fault quotes its message (measured on the pin with the store file locked, both
            // editions: RegisteredServerException, 'Exception calling "Invoke" with "2" argument(s): "Unable to read the list
            // of previously registered servers ..."').
            Exception thrown = failure is TargetInvocationException && failure.InnerException is not null ? failure.InnerException : failure;
            surfaceFault(new ErrorRecord(new MethodInvocationException(MethodFault("Invoke", 2, thrown), thrown), thrown.GetType().Name, ErrorCategory.NotSpecified, null));
            return null;
        }

        return localStore;
    }

    // PS: Copy-Item -Path $regfile -Destination $file -Force. Its failures are non-terminating records, and the command goes on.
    private static void CopyTemplateStore(PSCmdlet cmdlet, string file)
    {
        string template = (SystemHost.ModuleBase ?? String.Empty) + "\\bin\\RegSrvr.xml";
        try
        {
            cmdlet.SessionState.InvokeProvider.Item.Copy(new[] { template }, file, false, CopyContainers.CopyTargetContainer, true, false);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord? provider = (failure as IContainsErrorRecord)?.ErrorRecord;
            cmdlet.WriteError(provider is null ? new ErrorRecord(failure, "CopyItemFailure", ErrorCategory.WriteError, file) : new ErrorRecord(provider, failure));
        }
    }

    // PS: Test-Path -Path $file: false, with no record, for a path the provider cannot answer.
    private static bool TestPath(PSCmdlet cmdlet, string path)
    {
        try
        {
            return cmdlet.SessionState.InvokeProvider.Item.Exists(path);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            return false;
        }
    }

    // A statement of the pin outside any try: a plain call writes the record and goes on, a caller's try catches it, and
    // -EnableException stops here ("Operator decision: keep going unless -EnableException", point 3).
    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault outside Stop-Function, as in the pin
        }

        StatementFault.Surface(this, fault);
    }

    // The message PowerShell gives a failed .NET method call: 'Exception calling "X" with "N" argument(s): "..."'.
    private static string MethodFault(string method, int arguments, Exception failure)
    {
        return String.Format(CultureInfo.InvariantCulture, "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"",
            method, arguments, failure.Message);
    }
}
