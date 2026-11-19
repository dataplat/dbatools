#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Security;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Changes the value, type, description, sensitivity or name of an SSIS catalog environment variable.</para>
/// <para type="description">Drives the three catalog procedures that mutate an environment variable: catalog.set_environment_variable_protection for the sensitivity flag, catalog.set_environment_variable_property for the type, the description and the name, and catalog.set_environment_variable_value for the value.</para>
/// <para type="description">They are applied in a fixed order - sensitivity, type, value, description, name - so a variable being promoted never has its new value written in the clear first, and everything before the rename still addresses the variable by the name it was resolved under.</para>
/// <para type="description">Sensitivity only goes one way. The catalog refuses to turn a sensitive variable back into a plain one, so -Sensitive:$false against a sensitive variable is refused here with an explanation rather than passed on to fail as a raw catalog error; the variable has to be removed and recreated.</para>
/// <para type="description">A sensitive variable's value is supplied with -SecureValue and never with -Value, and -SecureValue is refused for a variable that is not sensitive and is not being made sensitive in the same call.</para>
/// <para type="description">-DataType converts what is already stored, decrypting and re-encrypting first for a sensitive variable. The catalog's conversion is lossy and does not refuse: on SQL 2019 a String variable holding "not a number" becomes Int32 0 and one holding "abc" becomes the current DateTime, both silently. Supply -Value in the same call whenever the variable already holds something you care about, and the command warns when you do not.</para>
/// </summary>
/// <example>
///   <code>PS C:\&gt; Set-DbaSsisEnvironmentVariable -SqlInstance sql2019 -Folder Finance -Environment Production -Variable BatchSize -Value 500</code>
///   <para>Sets the value of the BatchSize variable.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Set-DbaSsisEnvironmentVariable -SqlInstance sql2019 -Folder Finance -Environment Production -Variable ApiKey -SecureValue (Read-Host -AsSecureString) -Sensitive</code>
///   <para>Makes the variable sensitive and stores the new value encrypted. The promotion happens first, so the value is never written in the clear.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Set-DbaSsisEnvironmentVariable -SqlInstance sql2019 -Folder Finance -Environment Production -Variable Retries -DataType Int32 -Value 3</code>
///   <para>Changes the type and the value. The type change converts what is stored, so it is refused when the value already there does not fit the new type.</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; New-DbaSsisEnvironmentVariable -SqlInstance sql2019 -Folder Finance -Environment Production -Variable Retries -Value 1 | Set-DbaSsisEnvironmentVariable -Description "How many times a failed task is retried"</code>
///   <para>Pipes a variable straight into the change. Anything carrying SqlInstance, Folder, Environment and Name is accepted.</para>
/// </example>
[Cmdlet(VerbsCommon.Set, "DbaSsisEnvironmentVariable", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed partial class SetDbaSsisEnvironmentVariableCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The folders the environments live in. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 2)]
    public string[]? Folder { get; set; }

    /// <summary>The environments the variables live in. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 3)]
    public string[]? Environment { get; set; }

    /// <summary>The variables to change. Names are matched exactly - this is a name list, not a pattern.</summary>
    [Parameter(Position = 4)]
    [Alias("Name")]
    public string[]? Variable { get; set; }

    /// <summary>The new value for a variable that is not sensitive. Pass the real .NET type - the catalog stores it in a sql_variant and checks it against the variable's declared type.</summary>
    [Parameter(Position = 5)]
    public object? Value { get; set; }

    /// <summary>The new value for a sensitive variable. This is the only way to supply one.</summary>
    [Parameter(Position = 6)]
    public SecureString? SecureValue { get; set; }

    /// <summary>The new description. An empty string clears it; omitting the parameter leaves the description alone.</summary>
    [Parameter(Position = 7)]
    public string? Description { get; set; }

    /// <summary>The SSIS type name to convert the variable to. The catalog converts the stored value and substitutes a default rather than failing, so pass -Value in the same call unless you are content to lose what the variable holds.</summary>
    [Parameter(Position = 8)]
    public string? DataType { get; set; }

    /// <summary>The new variable name. Renames a single variable, and it happens after every other change.</summary>
    [Parameter(Position = 9)]
    public string? NewName { get; set; }

    /// <summary>Stores the variable encrypted. -Sensitive:$false is refused against a variable that is already sensitive - the catalog does not support it.</summary>
    [Parameter]
    public SwitchParameter Sensitive { get; set; }

    /// <summary>SSIS catalog environment variable objects, typically from Get-DbaSsisEnvironmentVariable or New-DbaSsisEnvironmentVariable.</summary>
    [Parameter(ValueFromPipeline = true)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>A variable selected for change, with the two stored facts every guard here turns on.</summary>
    private sealed class VariableTarget
    {
        internal Server Server = null!;
        internal string FolderName = null!;
        internal string EnvironmentName = null!;
        internal string Name = null!;
        internal bool IsSensitive;
        internal string StoredDataType = null!;
    }

    private readonly List<VariableTarget> _renameTargets = new();
    private bool _explicitTargetsExpanded;

    protected override void BeginProcessing()
    {
        // None of the changing parameters bound means the command would report success while
        // changing nothing, which is the failure mode that reads as "it worked".
        if (!TestBound(nameof(Value), nameof(SecureValue), nameof(Description), nameof(DataType), nameof(NewName), nameof(Sensitive)))
        {
            StopFunction("You must supply at least one of -Value, -SecureValue, -Description, -DataType, -NewName or -Sensitive; with none of them there is nothing to change", category: ErrorCategory.InvalidArgument);
            return;
        }

        // Settled before anything connects: a secret arriving through the plain -Value parameter
        // has already reached the caller's history by the time a connection would have opened.
        if (TestBound(nameof(Value)) && TestBound(nameof(SecureValue)))
        {
            StopFunction("You must supply either -Value or -SecureValue, not both", category: ErrorCategory.InvalidArgument);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Duality, no parameter sets. Checked here, not in BeginProcessing, because a
        // pipeline-bound InputObject is not in BoundParameters until ProcessRecord.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        List<VariableTarget> targets = new();

        // -SqlInstance is not pipeline-bound, so it is supplied once however many records arrive.
        // Expanding it per record would apply the change once per piped object and emit each
        // variable that many times.
        if (TestBound(nameof(SqlInstance)) && !_explicitTargetsExpanded)
        {
            _explicitTargetsExpanded = true;
            // With no selector at all the selection is every variable in the catalog, which is not
            // what anyone means by "set a value".
            if (!TestBound(nameof(Folder), nameof(Environment), nameof(Variable)))
            {
                StopFunction("You must supply -Folder, -Environment or -Variable when connecting with -SqlInstance");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server server = ResolveServer(instance);
                if (server == null)
                {
                    continue;
                }

                List<VariableTarget> resolved = ResolveVariables(server, Folder, Environment, Variable);
                targets.AddRange(resolved);
                ReportUnmatchedNames(instance, resolved);
            }
        }

        foreach (PSObject piped in InputObject ?? Array.Empty<PSObject>())
        {
            string? instanceName = PropertyText(piped, "SqlInstance");
            string? folderName = PropertyText(piped, "Folder");
            string? environmentName = PropertyText(piped, "Environment");
            string? variableName = PropertyText(piped, "Name");
            // There is no dbatools type name to check: the read command emits a plain
            // PSCustomObject and the create command emits an undecorated PSObject, so the four
            // properties that make up a variable's address are what identifies one.
            if (String.IsNullOrEmpty(instanceName) || String.IsNullOrEmpty(folderName) || String.IsNullOrEmpty(environmentName) || String.IsNullOrEmpty(variableName))
            {
                StopFunction("Input object is not an SSIS environment variable; it must carry SqlInstance, Folder, Environment and Name", target: piped, category: ErrorCategory.InvalidData, continueLoop: true);
                continue;
            }

            Server server = ResolveServer(new DbaInstanceParameter(instanceName!));
            if (server == null)
            {
                continue;
            }

            List<VariableTarget> resolved = ResolveVariables(server, new[] { folderName! }, new[] { environmentName! }, new[] { variableName! });
            if (resolved.Count == 0)
            {
                StopFunction($"SSIS environment variable {variableName} does not exist in {folderName}\\{environmentName} on {instanceName}", target: piped, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            targets.AddRange(resolved);
        }

        // A rename is held back until the pipeline has finished feeding, because the count that
        // decides whether it is legal is the count across the whole invocation - a per-record
        // check would have renamed the first variable before the second one arrived to refuse it.
        if (TestBound(nameof(NewName)))
        {
            _renameTargets.AddRange(targets);
            return;
        }

        foreach (VariableTarget target in targets)
        {
            ApplyChanges(target);
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted || !TestBound(nameof(NewName)))
        {
            return;
        }

        if (_renameTargets.Count > 1)
        {
            StringBuilder names = new();
            foreach (VariableTarget target in _renameTargets)
            {
                if (names.Length > 0)
                {
                    names.Append(", ");
                }
                names.Append(target.FolderName).Append('\\').Append(target.EnvironmentName).Append('\\').Append(target.Name);
            }

            StopFunction($"-NewName renames one variable, and the selection resolved to {_renameTargets.Count.ToString(CultureInfo.InvariantCulture)} ({names}); nothing was changed", category: ErrorCategory.InvalidArgument);
            return;
        }

        foreach (VariableTarget target in _renameTargets)
        {
            ApplyChanges(target);
        }
    }

    /// <summary>
    /// The fixed order the design turns on: sensitivity, type, value, description, name. Promoting
    /// before the value is written keeps a new secret out of the plaintext column even briefly, and
    /// renaming last leaves every earlier call addressing the name the variable was resolved under.
    /// Each step is attempted rather than short-circuited on a declined ShouldProcess, so -WhatIf
    /// reports all of them instead of going quiet after the first.
    /// </summary>
    private void ApplyChanges(VariableTarget target)
    {
        if (!ValidateTarget(target))
        {
            return;
        }

        bool protectionSet = ApplyProtection(target);
        bool typeSet = ApplyDataType(target);
        bool valueSet = ApplyValue(target);
        bool describedSet = ApplyDescription(target);
        bool renamed = ApplyRename(target);

        if (protectionSet && typeSet && valueSet && describedSet && renamed)
        {
            EmitVariable(target);
        }
    }

    /// <summary>
    /// What the caller asked for against what the variable actually is. All three refusals are
    /// conditions the server would report as a bare catalog error, and two of them would report it
    /// only after an earlier change had already landed.
    /// </summary>
    private bool ValidateTarget(VariableTarget target)
    {
        string address = $"{target.Name} in {target.FolderName}\\{target.EnvironmentName}";
        bool willBeSensitive = TestBound(nameof(Sensitive)) ? Sensitive.ToBool() : target.IsSensitive;

        // The catalog's own check: set_environment_variable_protection raises when @sensitive is 0
        // and the stored value is sensitive. There is no way back, so the message says what to do.
        if (TestBound(nameof(Sensitive)) && !Sensitive.ToBool() && target.IsSensitive)
        {
            StopFunction($"SSIS environment variable {address} is sensitive and the catalog cannot make it plain again; remove it and create it without -Sensitive", target: target.Name, category: ErrorCategory.InvalidOperation, continueLoop: true);
            return false;
        }

        if (TestBound(nameof(Value)) && willBeSensitive)
        {
            StopFunction($"SSIS environment variable {address} is sensitive; supply its value with -SecureValue, never with -Value", target: target.Name, category: ErrorCategory.InvalidArgument, continueLoop: true);
            return false;
        }

        if (TestBound(nameof(SecureValue)) && !willBeSensitive)
        {
            StopFunction($"SSIS environment variable {address} is not sensitive; -SecureValue needs -Sensitive in the same call, because a value supplied securely and then stored in the clear is a false assurance", target: target.Name, category: ErrorCategory.InvalidArgument, continueLoop: true);
            return false;
        }

        return true;
    }

}
