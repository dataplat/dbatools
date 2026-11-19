#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Runtime.InteropServices;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.dbaSystem;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using DmfCondition = Microsoft.SqlServer.Management.Dmf.Condition;
using DmfObjectSet = Microsoft.SqlServer.Management.Dmf.ObjectSet;
using DmfPolicy = Microsoft.SqlServer.Management.Dmf.Policy;
using DmfPolicyCategory = Microsoft.SqlServer.Management.Dmf.PolicyCategory;
using DmfPolicyStore = Microsoft.SqlServer.Management.Dmf.PolicyStore;
using DmfTargetSet = Microsoft.SqlServer.Management.Dmf.TargetSet;
using DmfTargetSetLevel = Microsoft.SqlServer.Management.Dmf.TargetSetLevel;
using SfcCreatable = Microsoft.SqlServer.Management.Sdk.Sfc.ISfcCreatable;
using SfcScript = Microsoft.SqlServer.Management.Sdk.Sfc.ISfcScript;
using SfcTSqlScript = Microsoft.SqlServer.Management.Sdk.Sfc.SfcTSqlScript;
using SqlStoreConnection = Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection;

namespace Dataplat.Dbatools.Commands;

/// <summary>Copies Policy-Based Management policies, conditions, and categories between SQL Server instances</summary>
[Cmdlet(VerbsCommon.Copy, "DbaPolicyManagement", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaPolicyManagementCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance. Requires sysadmin and SQL Server 2008 or higher.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Destination SQL Server instances. Requires sysadmin and SQL Server 2008 or higher.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy the policies with these names.</summary>
    [Parameter(Position = 4)]
    public object[]? Policy { get; set; }

    /// <summary>Skip the policies with these names.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludePolicy { get; set; }

    /// <summary>Only copy the conditions with these names.</summary>
    [Parameter(Position = 6)]
    public object[]? Condition { get; set; }

    /// <summary>Skip the conditions with these names.</summary>
    [Parameter(Position = 7)]
    public object[]? ExcludeCondition { get; set; }

    /// <summary>Drop and recreate conditions and policies that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Server? _source;
    private DmfPolicyStore? _sourceStore;
    private List<DmfPolicy> _storePolicies = new();
    private List<DmfCondition> _storeConditions = new();
    private List<DmfObjectSet> _storeObjectSets = new();
    // Upstream correction (wrong data): the pinned loops "foreach ($condition in ...)" and "foreach ($policy in ...)"
    // assign the parameters $Condition and $Policy (variable names ignore case), so every destination after the first
    // was filtered by the last copied object and received nothing. The filters keep the caller's values.
    private object[]? _policyFilter;
    private object[]? _conditionFilter;

    protected override void BeginProcessing()
    {
        _policyFilter = Policy;
        _conditionFilter = Condition;

        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            StopFunction("Copy-DbaPolicyManagement does not support Linux - we're still waiting for the Core SMOs from Microsoft");
            return;
        }

        AddPbmLibrary();
        _source = Connect(Source, SourceSqlCredential, false);
        if (_source is null)
            return;

        _sourceStore = Store(_source);
        foreach (DmfPolicy policy in _sourceStore.Policies)
        {
            if (!policy.IsSystemObject)
                _storePolicies.Add(policy);
        }
        foreach (DmfCondition condition in _sourceStore.Conditions)
        {
            if (!condition.IsSystemObject)
                _storeConditions.Add(condition);
        }
        foreach (DmfObjectSet objectSet in _sourceStore.ObjectSets)
        {
            if (!objectSet.IsSystemObject)
                _storeObjectSets.Add(objectSet);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _source is null || _sourceStore is null)
            return;

        // Messages and the category ShouldProcess calls name the whole -Destination array, as the pinned text does
        // with $destination.
        string destinationText = String.Join(" ", Array.ConvertAll(Destination, instance => instance?.ToString() ?? ""));

        foreach (DbaInstanceParameter destInstance in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? destServer = Connect(destInstance, DestinationSqlCredential, true);
            if (destServer is null)
                continue;
            DmfPolicyStore destStore = Store(destServer);
            string destinationName = destInstance.ToString();

            List<DmfPolicy>? storePoliciesToCopy = _storePolicies;
            List<DmfCondition>? storeConditionsToCopy = _storeConditions;
            List<DmfObjectSet> storeObjectSetsToCopy = _storeObjectSets;

            if (LanguagePrimitives.IsTrue(_policyFilter))
                storePoliciesToCopy = storePoliciesToCopy.FindAll(policy => In(_policyFilter!, policy.Name));
            if (LanguagePrimitives.IsTrue(ExcludePolicy))
                storePoliciesToCopy = storePoliciesToCopy.FindAll(policy => !In(ExcludePolicy!, policy.Name));
            if (LanguagePrimitives.IsTrue(_conditionFilter))
                storeConditionsToCopy = storeConditionsToCopy.FindAll(condition => In(_conditionFilter!, condition.Name));
            if (LanguagePrimitives.IsTrue(ExcludeCondition))
                storeConditionsToCopy = storeConditionsToCopy.FindAll(condition => !In(ExcludeCondition!, condition.Name));

            if (LanguagePrimitives.IsTrue(_policyFilter) && LanguagePrimitives.IsTrue(_conditionFilter))
            {
                storeConditionsToCopy = null;
                storePoliciesToCopy = null;
            }

            // Upstream correction (unsafe change): with -Policy and no -Condition the pinned function copied every
            // source condition, and with -Force dropped and recreated each one the destination already held, together
            // with the destination policies that depend on it, although the -Policy help says only the selected
            // policies and their dependent conditions are copied. Here the conditions are the ones the selected
            // policies use, still subject to -ExcludeCondition.
            if (LanguagePrimitives.IsTrue(_policyFilter) && !LanguagePrimitives.IsTrue(_conditionFilter) && storeConditionsToCopy is not null)
            {
                HashSet<string> dependentConditions = DependentConditions(storePoliciesToCopy);
                storeConditionsToCopy = storeConditionsToCopy.FindAll(condition => dependentConditions.Contains(condition.Name));
            }

            if (LanguagePrimitives.IsTrue(_policyFilter) || LanguagePrimitives.IsTrue(ExcludePolicy))
            {
                // Select-Object -ExpandProperty ObjectSet -Unique | Where-Object { $PSItem }
                List<object> requiredObjectSets = new();
                foreach (DmfPolicy policy in storePoliciesToCopy ?? new List<DmfPolicy>())
                {
                    if (LanguagePrimitives.IsTrue(policy.ObjectSet))
                        requiredObjectSets.Add(policy.ObjectSet);
                }
                storeObjectSetsToCopy = storeObjectSetsToCopy.FindAll(objectSet => In(requiredObjectSets.ToArray(), objectSet.Name));
            }

            CopyCategories(destServer, destStore, storePoliciesToCopy, destinationName, destinationText);
            CopyConditions(destServer, destStore, storeConditionsToCopy, storePoliciesToCopy, destinationName);
            CopyObjectSets(destServer, destStore, storeObjectSetsToCopy, destinationName);
            CopyPolicies(destServer, destStore, storePoliciesToCopy, destinationName);
        }
    }

    private void CopyCategories(Server destServer, DmfPolicyStore destStore, List<DmfPolicy>? policies, string destinationName,
        string destinationText)
    {
        WriteMessage(MessageLevel.Verbose, "Migrating categories");
        List<object> uniquePolicyCategories = new();
        foreach (DmfPolicy policy in policies ?? new List<DmfPolicy>())
            uniquePolicyCategories.Add(policy.PolicyCategory);

        foreach (DmfPolicyCategory category in _sourceStore!.PolicyCategories)
        {
            if (!In(uniquePolicyCategories.ToArray(), category.Name))
                continue;
            string categoryName = category.Name;
            PSObject copyCategoryStatus = Status(destServer, categoryName, "Policy Category");

            // Upstream correction (wrong data): the pinned check reads the category named Database for every category,
            // so a category the destination holds was created again and reported Failed, and with a Database category
            // every category was reported as already existing. The destination is asked for this category.
            if (destStore.PolicyCategories[categoryName] is not null)
            {
                if (Confirm(destinationName, String.Format("Policy category '{0}' was skipped because it already exists on {1}", categoryName, destinationText)))
                {
                    WriteMessage(MessageLevel.Verbose, String.Format("Policy category '{0}' was skipped because it already exists on {1}.", categoryName, destinationText));
                    Emit(copyCategoryStatus, "Skipped", "Already exists on destination");
                }
                continue;
            }

            if (Confirm(destinationText, "Migrating policy category " + categoryName))
            {
                try
                {
                    // PolicyCategory implements ScriptCreate only as ISfcCreatable.ScriptCreate (Microsoft Learn,
                    // PolicyCategory class, explicit interface implementations).
                    string sql = ScriptText(Call("ScriptCreate", () => ((SfcCreatable)category).ScriptCreate()));
                    WriteMessage(MessageLevel.Debug, sql);
                    WriteMessage(MessageLevel.Verbose, "Copying policy category " + categoryName);
                    Query(destServer, sql);
                    Call("Refresh", () => destStore.PolicyCategories.Refresh());
                    Emit(copyCategoryStatus, "Successful", null);
                }
                catch (MethodFault failure)
                {
                    Emit(copyCategoryStatus, "Failed", failure.Message);
                    WriteMessage(MessageLevel.Verbose, String.Format("Issue copying policy category {0} on {1} | {2}", categoryName, destinationName, failure.Message));
                }
            }
        }
    }

    /// <summary>
    /// The conditions the given policies use: each policy's Condition and RootCondition, and the condition of every
    /// target set level of its object set (Microsoft Learn: Policy.Condition, Policy.RootCondition,
    /// ObjectSet.TargetSets, TargetSet.Levels, TargetSetLevel.Condition, each naming a PolicyStore condition).
    /// </summary>
    private HashSet<string> DependentConditions(List<DmfPolicy>? policies)
    {
        HashSet<string> names = new(StringComparer.OrdinalIgnoreCase);
        foreach (DmfPolicy policy in policies ?? new List<DmfPolicy>())
        {
            AddConditionName(names, policy.Condition);
            AddConditionName(names, policy.RootCondition);
            if (String.IsNullOrEmpty(policy.ObjectSet))
                continue;
            DmfObjectSet? objectSet = _sourceStore!.ObjectSets[policy.ObjectSet];
            if (objectSet is null)
                continue;
            foreach (DmfTargetSet targetSet in objectSet.TargetSets)
            {
                foreach (DmfTargetSetLevel level in targetSet.Levels)
                    AddConditionName(names, level.Condition);
            }
        }
        return names;
    }

    private static void AddConditionName(HashSet<string> names, string? name)
    {
        if (!String.IsNullOrEmpty(name))
            names.Add(name!);
    }

    private void CopyConditions(Server destServer, DmfPolicyStore destStore, List<DmfCondition>? conditions, List<DmfPolicy>? copiedPolicies,
        string destinationName)
    {
        WriteMessage(MessageLevel.Verbose, "Migrating conditions");
        foreach (DmfCondition condition in conditions ?? new List<DmfCondition>())
        {
            string conditionName = condition.Name;
            PSObject copyConditionStatus = Status(destServer, conditionName, "Policy Condition");
            List<KeptPolicy> keptPolicies = new();

            if (destStore.Conditions[conditionName] is not null)
            {
                if (!Force)
                {
                    if (Confirm(destinationName, String.Format("Condition '{0}' was skipped because it already exists on {1}. Use -Force to drop and recreate", conditionName, destinationName)))
                    {
                        WriteMessage(MessageLevel.Verbose, String.Format("condition '{0}' was skipped because it already exists on {1}. Use -Force to drop and recreate", conditionName, destinationName));
                        Emit(copyConditionStatus, "Skipped", "Already exists on destination");
                    }
                    continue;
                }
                if (Confirm(destinationName, "Attempting to drop policy condition " + conditionName))
                {
                    WriteMessage(MessageLevel.Verbose, String.Format("Condition '{0}' exists on {1}. Force specified. Dropping {0}.", conditionName, destinationName));
                    try
                    {
                        IEnumerable<DmfPolicy> dependentPolicies = Call("EnumDependentPolicies", () => destStore.Conditions[conditionName].EnumDependentPolicies());
                        keptPolicies = ScriptKeptPolicies(destStore, dependentPolicies, copiedPolicies);
                        foreach (DmfPolicy dependent in dependentPolicies)
                        {
                            Call("Drop", () => dependent.Drop());
                            Call("Refresh", () => destStore.Conditions.Refresh());
                        }
                        Call("Drop", () => destStore.Conditions[conditionName].Drop());
                    }
                    catch (MethodFault failure)
                    {
                        Emit(copyConditionStatus, "Failed", MessageService.GetErrorMessage(failure.Record()));
                        WriteMessage(MessageLevel.Verbose, String.Format("Issue dropping policy condition {0} on {1} | {2}", conditionName, destinationName, failure.Message));
                        RestoreKeptPolicies(destServer, destStore, keptPolicies, destinationName);
                        continue;
                    }
                }
            }

            if (Confirm(destinationName, "Migrating condition " + conditionName))
            {
                try
                {
                    string sql = ScriptText(Call("ScriptCreate", () => condition.ScriptCreate()));
                    WriteMessage(MessageLevel.Debug, sql);
                    WriteMessage(MessageLevel.Verbose, "Copying condition " + conditionName);
                    Query(destServer, sql);
                    Call("Refresh", () => destStore.Conditions.Refresh());
                    Emit(copyConditionStatus, "Successful", null);
                }
                catch (MethodFault failure)
                {
                    Emit(copyConditionStatus, "Failed", MessageService.GetErrorMessage(failure.Record()));
                    WriteMessage(MessageLevel.Verbose, String.Format("Issue creating policy condition {0} on {1} | {2}", conditionName, destinationName, failure.Message));
                }
            }
            RestoreKeptPolicies(destServer, destStore, keptPolicies, destinationName);
        }
    }

    // Upstream correction (unsafe change): with -Force the pinned function dropped every destination policy that uses
    // an existing condition before dropping and recreating it, and recreated only the policies it copied, so every
    // other policy on that condition was deleted for good. Each dependent this call does not copy itself is scripted
    // first, with its object set (Policy.ScriptCreate leaves the object set out, Microsoft Learn), and recreated after
    // the condition.
    private List<KeptPolicy> ScriptKeptPolicies(DmfPolicyStore destStore, IEnumerable<DmfPolicy> dependentPolicies,
        List<DmfPolicy>? copiedPolicies)
    {
        List<object> copiedNames = new();
        foreach (DmfPolicy policy in copiedPolicies ?? new List<DmfPolicy>())
            copiedNames.Add(policy.Name);

        List<KeptPolicy> keptPolicies = new();
        foreach (DmfPolicy dependent in dependentPolicies)
        {
            string dependentName = dependent.Name;
            if (In(copiedNames.ToArray(), dependentName))
                continue;
            string objectSetName = dependent.ObjectSet ?? "";
            string? objectSetScript = null;
            if (objectSetName.Length > 0)
            {
                if (destStore.ObjectSets[objectSetName] is DmfObjectSet objectSet)
                    objectSetScript = ScriptText(Call("ScriptCreate", () => objectSet.ScriptCreate()));
            }
            string policyScript = ScriptText(Call("ScriptCreate", () => dependent.ScriptCreate()));
            keptPolicies.Add(new KeptPolicy(dependentName, objectSetName, objectSetScript, policyScript));
        }
        return keptPolicies;
    }

    // Recreates the scripted dependents that are gone: the object set first when it no longer exists, then the policy.
    // A policy that still exists was never dropped. A failure is reported as the policy copy reports one.
    private void RestoreKeptPolicies(Server destServer, DmfPolicyStore destStore, List<KeptPolicy> keptPolicies, string destinationName)
    {
        foreach (KeptPolicy kept in keptPolicies)
        {
            try
            {
                Call("Refresh", () => destStore.Policies.Refresh());
                if (destStore.Policies[kept.Name] is not null)
                    continue;
                if (kept.ObjectSetScript is not null)
                {
                    Call("Refresh", () => destStore.ObjectSets.Refresh());
                    if (destStore.ObjectSets[kept.ObjectSetName] is null)
                    {
                        WriteMessage(MessageLevel.Debug, kept.ObjectSetScript);
                        Query(destServer, kept.ObjectSetScript);
                    }
                }
                WriteMessage(MessageLevel.Debug, kept.PolicyScript);
                Query(destServer, kept.PolicyScript);
                Call("Refresh", () => destStore.Policies.Refresh());
            }
            catch (MethodFault failure)
            {
                Emit(Status(destServer, kept.Name, "Policy"), "Failed", MessageService.GetErrorMessage(failure.Record()));
                WriteMessage(MessageLevel.Verbose, String.Format("Issue creating policy {0} on {1} | {2}", kept.Name, destinationName, failure.Message));
            }
        }
    }

    private void CopyObjectSets(Server destServer, DmfPolicyStore destStore, List<DmfObjectSet> objectSets, string destinationName)
    {
        WriteMessage(MessageLevel.Verbose, "Migrating object sets");
        foreach (DmfObjectSet objectSet in objectSets)
        {
            string objectSetName = objectSet.Name;
            PSObject copyObjectSetStatus = Status(destServer, objectSetName, "Policy ObjectSet");

            if (destStore.ObjectSets[objectSetName] is not null)
            {
                if (Confirm(destinationName, String.Format("ObjectSet '{0}' was skipped because it already exists on {1}", objectSetName, destinationName)))
                {
                    WriteMessage(MessageLevel.Verbose, String.Format("ObjectSet '{0}' was skipped because it already exists on {1}.", objectSetName, destinationName));
                    Emit(copyObjectSetStatus, "Skipped", "Already exists on destination");
                }
                continue;
            }

            if (Confirm(destinationName, "Migrating object set " + objectSetName))
            {
                try
                {
                    string sql = ScriptText(Call("ScriptCreate", () => objectSet.ScriptCreate()));
                    WriteMessage(MessageLevel.Debug, sql);
                    WriteMessage(MessageLevel.Verbose, "Copying object set " + objectSetName);
                    Query(destServer, sql);
                    Call("Refresh", () => destStore.ObjectSets.Refresh());
                    Emit(copyObjectSetStatus, "Successful", null);
                }
                catch (MethodFault failure)
                {
                    Emit(copyObjectSetStatus, "Failed", MessageService.GetErrorMessage(failure.Record()));
                    WriteMessage(MessageLevel.Verbose, String.Format("Issue creating object set {0} on {1} | {2}", objectSetName, destinationName, failure.Message));
                }
            }
        }
    }

    private void CopyPolicies(Server destServer, DmfPolicyStore destStore, List<DmfPolicy>? policies, string destinationName)
    {
        WriteMessage(MessageLevel.Verbose, "Migrating policies");
        foreach (DmfPolicy policy in policies ?? new List<DmfPolicy>())
        {
            string policyName = policy.Name;
            PSObject copyPolicyStatus = Status(destServer, policyName, "Policy");

            if (destStore.Policies[policyName] is not null)
            {
                if (!Force)
                {
                    if (Confirm(destinationName, String.Format("Policy '{0}' was skipped because it already exists on {1}. Use -Force to drop and recreate", policyName, destinationName)))
                    {
                        WriteMessage(MessageLevel.Verbose, String.Format("Policy '{0}' was skipped because it already exists on {1}. Use -Force to drop and recreate", policyName, destinationName));
                        Emit(copyPolicyStatus, "Skipped", "Already exists on destination");
                    }
                    continue;
                }
                if (Confirm(destinationName, "Attempting to drop " + policyName))
                {
                    WriteMessage(MessageLevel.Verbose, String.Format("Policy '{0}' exists on {1}. Force specified. Dropping {0}.", policyName, destinationName));
                    try
                    {
                        Call("Drop", () => destStore.Policies[policyName].Drop());
                        Call("refresh", () => destStore.Policies.Refresh());
                    }
                    catch (MethodFault failure)
                    {
                        Emit(copyPolicyStatus, "Failed", MessageService.GetErrorMessage(failure.Record()));
                        WriteMessage(MessageLevel.Verbose, String.Format("Issue creating policy {0} on {1} | {2}", policyName, destinationName, failure.Message));
                        continue;
                    }
                }
            }

            if (Confirm(destinationName, "Migrating policy " + policyName))
            {
                try
                {
                    Call("Refresh", () => destStore.Conditions.Refresh());
                    Call("Refresh", () => destStore.Policies.Refresh());
                    string sql = ScriptText(Call("ScriptCreate", () => policy.ScriptCreate()));
                    WriteMessage(MessageLevel.Debug, sql);
                    WriteMessage(MessageLevel.Verbose, "Copying policy " + policyName);
                    Query(destServer, sql);
                    Emit(copyPolicyStatus, "Successful", null);
                }
                catch (MethodFault failure)
                {
                    Emit(copyPolicyStatus, "Failed", MessageService.GetErrorMessage(failure.Record()));
                    // This is usually because of a duplicate dependent from above. Just skip for now.
                    WriteMessage(MessageLevel.Verbose, String.Format("Issue creating policy {0} on {1} | {2}", policyName, destinationName, failure.Message));
                }
            }
        }
    }

    // Add-PbmLibrary: loads the DMF assemblies from the library's lib folder. Its Stop-Function runs in the helper's
    // own scope without -EnableException, so a failure warns and does not stop this command.
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

    private Server? Connect(DbaInstanceParameter instance, PSCredential? credential, bool continueLoop)
    {
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(new SmoConnectionRequest
            {
                Instance = instance,
                SqlCredential = credential,
                MinimumVersion = 10,
                // Upstream correction (unsafe change): Policy-Based Management lives in msdb, which Azure SQL Database
                // does not have, so both ends refuse it as Connect-DbaInstance -AzureUnsupported does.
                AzureUnsupported = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "MinimumVersion", "AzureUnsupported" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            });
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StopFunction("Failure", target: instance,
                errorRecord: new ErrorRecord(failure, "dbatools_Copy-DbaPolicyManagement", ErrorCategory.ConnectionError, instance),
                category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    // New-Object Microsoft.SqlServer.Management.DMF.PolicyStore (New-Object ...SqlStoreConnection $server.ConnectionContext.SqlConnectionObject)
    private static DmfPolicyStore Store(Server server)
    {
        return new DmfPolicyStore(new SqlStoreConnection(server.ConnectionContext.SqlConnectionObject));
    }

    // -Force sets $ConfirmPreference to 'none' for the whole function in the pinned begin block.
    private bool Confirm(string target, string action)
    {
        if (!Force)
            return ShouldProcess(target, action);
        object? previousPreference = SessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            SessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return ShouldProcess(target, action);
        }
        finally
        {
            SessionState.PSVariable.Set("ConfirmPreference", previousPreference);
        }
    }

    // $object.ScriptCreate().GetScript() | Out-String: every line of the script followed by a line break.
    private static string ScriptText(SfcScript script)
    {
        StringCollection lines = Call("GetScript", () =>
        {
            if (script is SfcTSqlScript tsql)
                return tsql.GetScript();
            throw new MissingMethodException(script.GetType().FullName, "GetScript");
        });
        string text = "";
        foreach (string? line in lines)
            text += line + Environment.NewLine;
        return text;
    }

    // Server.Query: the batch runs on the connection; its rows are not used here.
    private static void Query(Server server, string sql)
    {
        try
        {
            server.ConnectionContext.ExecuteWithResults(sql);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            throw MethodFault.FromScriptMethod("Query", 1, failure);
        }
    }

    // A .NET method called from the pinned script: its failure reaches the catch block as the engine's method fault.
    private static T Call<T>(string method, Func<T> call)
    {
        try
        {
            return call();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException && failure is not MethodFault)
        {
            throw new MethodFault(method, 0, failure.Message, failure);
        }
    }

    private static void Call(string method, Action call)
    {
        Call<object?>(method, () =>
        {
            call();
            return null;
        });
    }

    // PowerShell -in: the name equals an element of the list, compared as -eq compares (strings ignore case).
    private static bool In(object[] values, string name)
    {
        foreach (object value in values)
        {
            if (LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    private PSObject Status(Server destServer, string name, string type)
    {
        PSObject result = new();
        result.Properties.Add(new PSNoteProperty("SourceServer", _source!.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", destServer.Name));
        result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Type", type));
        result.Properties.Add(new PSNoteProperty("Status", null));
        result.Properties.Add(new PSNoteProperty("Notes", null));
        result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(DateTime.Now)));
        return result;
    }

    // Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
    private void Emit(PSObject result, string status, string? notes)
    {
        result.Properties["Status"].Value = status;
        result.Properties["Notes"].Value = notes;
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        OutputHelper.InsertTypeName(result, "MigrationObject");
        WriteObject(result);
    }

    // A destination policy scripted before its condition is dropped: its object set's script when the set exists.
    private sealed class KeptPolicy
    {
        public KeptPolicy(string name, string objectSetName, string? objectSetScript, string policyScript)
        {
            Name = name;
            ObjectSetName = objectSetName;
            ObjectSetScript = objectSetScript;
            PolicyScript = policyScript;
        }

        public string Name { get; }
        public string ObjectSetName { get; }
        public string? ObjectSetScript { get; }
        public string PolicyScript { get; }
    }

    // The fault a pinned catch block receives from a method call: the engine reports a failed .NET method as
    // 'Exception calling "<method>" with "<n>" argument(s): "<message>"' over the original exception, and the Query
    // script method throws the joined messages of the failure chain, which the engine wraps the same way.
    private sealed class MethodFault : Exception
    {
        private readonly Exception _inner;

        public MethodFault(string method, int arguments, string text, Exception inner)
            : base(String.Format(CultureInfo.InvariantCulture, "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, arguments, text), inner)
        {
            _inner = inner;
        }

        public static MethodFault FromScriptMethod(string method, int arguments, Exception failure)
        {
            string text = "";
            Exception current = failure;
            while (current.InnerException is not null)
            {
                text += current.Message;
                current = current.InnerException;
            }
            text += current.Message;
            return new MethodFault(method, arguments, text, new RuntimeException(text));
        }

        public ErrorRecord Record()
        {
            MethodInvocationException fault = new(Message, _inner);
            return new ErrorRecord(fault, "MethodInvocationException", ErrorCategory.NotSpecified, null);
        }
    }
}
