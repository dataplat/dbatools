#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Returns log entries from the in-memory dbatools log. Port of public/Get-DbatoolsLog.ps1:
/// LogHost.GetLog()/GetErrors() snapshots filtered through the function's conditional chain
/// (FunctionName/ModuleName -like, LastError re-read + last-1, TargetObject -eq, Tags -in,
/// Runspace -eq, the Get-History time window, Level -in), with the Get-History read and BOTH
/// Select-Object statements (the history -Last/-Skip slice and the 15-property projection
/// with its calculated Message ScriptBlock, passed VERBATIM so the flattening loop runs in
/// the engine) riding the REAL cmdlets through NestedCommand. -Raw emits the accumulated
/// pipeline value unprojected. Surface pinned by migration/baselines/Get-DbatoolsLog.json
/// (FunctionName pos0 ... Level pos7, switches non-positional).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbatoolsLog")]
[OutputType(typeof(PSObject))]
public sealed class GetDbatoolsLogCommand : DbaBaseCmdlet
{
    /// <summary>Filter by the function that wrote the entry, default "*".</summary>
    [Parameter(Position = 0)]
    public string FunctionName { get; set; } = "*";

    /// <summary>Filter by the module that wrote the entry, default "*".</summary>
    [Parameter(Position = 1)]
    public string ModuleName { get; set; } = "*";

    /// <summary>Filter by the target object of the entry.</summary>
    [AllowNull]
    [Parameter(Position = 2)]
    public object? Target { get; set; }

    /// <summary>Filter by entry tags.</summary>
    [Parameter(Position = 3)]
    public string[]? Tag { get; set; }

    /// <summary>Restrict to the last n executions from the session history.</summary>
    [Parameter(Position = 4)]
    public int Last { get; set; }

    /// <summary>Returns the last error-type log entry.</summary>
    [Parameter]
    public SwitchParameter LastError { get; set; }

    /// <summary>Skips n executions when -Last is used.</summary>
    [Parameter(Position = 5)]
    public int Skip { get; set; }

    /// <summary>Filter by the runspace that wrote the entry.</summary>
    [Parameter(Position = 6)]
    public Guid Runspace { get; set; }

    /// <summary>Filter by message level.</summary>
    [Parameter(Position = 7)]
    public MessageLevel[]? Level { get; set; }

    /// <summary>Emits the raw LogEntry objects instead of the projected view.</summary>
    [Parameter]
    public SwitchParameter Raw { get; set; }

    /// <summary>Reads the error log instead of the message log.</summary>
    [Parameter]
    public SwitchParameter Errors { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS: the Select-Object projection list; the Message hashtable's Expression runs the
    // VERBATIM scriptblock in the engine (newline join + double-space collapse loop).
    private const string MessageExpression = @"
                    $msg = ($_.Message.Split(""`n"") -join "" "")
                    do {
                        $msg = $msg.Replace('  ', ' ')
                    } until ($msg -notmatch '  ')
                    $msg
                ";

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        WildcardPattern functionPattern = WildcardPattern.Get(FunctionName, WildcardOptions.IgnoreCase);
        WildcardPattern modulePattern = WildcardPattern.Get(ModuleName, WildcardOptions.IgnoreCase);

        // PS: GetErrors()/GetLog() | Where-Object FunctionName/ModuleName -like
        List<object> messages = FilterByNames(Errors.IsPresent ? (IEnumerable)LogHost.GetErrors() : LogHost.GetLog(), functionPattern, modulePattern);

        if (TestBound("LastError"))
        {
            // PS: GetErrors() re-read + same -like filters + Select-Object -Last 1
            List<object> errorsFiltered = FilterByNames(LogHost.GetErrors(), functionPattern, modulePattern);
            messages = new List<object>();
            if (errorsFiltered.Count > 0)
            {
                messages.Add(errorsFiltered[errorsFiltered.Count - 1]);
            }
        }

        if (TestBound("Target"))
        {
            // PS: Where-Object TargetObject -eq $Target - an ARRAY LHS filters its elements
            // and the FILTERED RESULT's truthiness decides (codex W1-016 r1 finding 1; the
            // campaign PsEqTruthy class).
            messages = messages.FindAll(m => PsEqTruthy(DotProperty(m, "TargetObject"), Target));
        }

        if (TestBound("Tag"))
        {
            // PS: Where-Object { $_.Tags | Where-Object { $_ -in $Tag } } - the MATCHED TAG
            // VALUES drive the outer truthiness, so one matched empty-string tag is falsy
            // (codex W1-016 r1 finding 2).
            messages = messages.FindAll(m => MatchedTagsTruthy(DotProperty(m, "Tags")));
        }

        if (TestBound("Runspace"))
        {
            messages = messages.FindAll(m => PsEquals(DotProperty(m, "Runspace"), Runspace));
        }

        if (TestBound("Last"))
        {
            // PS: Get-History | Where CommandLine -NotLike "Get-DbatoolsLog*" |
            //     Select-Object -Last $Last -Skip $Skip - the history read and the
            //     -Last/-Skip slice both ride the engine.
            Collection<PSObject> history = NestedCommand.Invoke(this, "Get-History", new Hashtable());
            List<object> historyFiltered = new List<object>();
            WildcardPattern selfPattern = WildcardPattern.Get("Get-DbatoolsLog*", WildcardOptions.IgnoreCase);
            foreach (PSObject item in history)
            {
                string commandLine = LanguagePrimitives.ConvertTo<string>(DotProperty(item, "CommandLine")) ?? string.Empty;
                if (!selfPattern.IsMatch(commandLine))
                {
                    historyFiltered.Add(item);
                }
            }
            Hashtable splatSlice = new();
            splatSlice["Last"] = Last;
            splatSlice["Skip"] = Skip;
            Collection<PSObject> sliced = NestedCommand.Invoke(this, "Select-Object", splatSlice, pipelineInput: historyFiltered);

            // PS: $history[0].StartExecutionTime / $history[-1].EndExecutionTime - indexing
            // a NULL slice raises the statement-terminating "Cannot index into a null
            // array" error TWICE (one per statement; lab-proven - the smoke's empty-history
            // Function leg dies with FQEID NullArray under -ErrorAction Stop); the window
            // bounds then stay null and PS -gt/-lt null-conversion filters everything out.
            object? start = null;
            object? end = null;
            if (sliced.Count > 0)
            {
                start = DotProperty(sliced[0], "StartExecutionTime");
                end = DotProperty(sliced[sliced.Count - 1], "EndExecutionTime");
            }
            else
            {
                WriteError(new ErrorRecord(new RuntimeException("Cannot index into a null array."), "NullArray", ErrorCategory.InvalidOperation, null));
                WriteError(new ErrorRecord(new RuntimeException("Cannot index into a null array."), "NullArray", ErrorCategory.InvalidOperation, null));
            }
            Guid currentRunspace = System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId;
            messages = messages.FindAll(m =>
                PsGreaterThan(DotProperty(m, "Timestamp"), start)
                && PsLessThan(DotProperty(m, "Timestamp"), end)
                && PsEquals(DotProperty(m, "Runspace"), currentRunspace));
        }

        if (TestBound("Level"))
        {
            messages = messages.FindAll(m => LevelMatches(DotProperty(m, "Level")));
        }

        if (Raw.IsPresent)
        {
            // PS: return $messages - the pipeline enumerates the accumulated value
            foreach (object message in messages)
            {
                WriteObject(message);
            }
            return;
        }

        // PS: $messages | Select-Object -Property <14 names + the calculated Message>
        Hashtable messageProperty = new();
        messageProperty["Name"] = "Message";
        messageProperty["Expression"] = ScriptBlock.Create(MessageExpression);
        object[] projection =
        {
            "CallStack", "ComputerName", "File", "FunctionName", "Level", "Line",
            messageProperty, "ModuleName", "Runspace", "Tags", "TargetObject", "Timestamp",
            "Type", "Username"
        };
        Hashtable splatProject = new();
        splatProject["Property"] = projection;
        Collection<PSObject> output = NestedCommand.Invoke(this, "Select-Object", splatProject, pipelineInput: messages);
        foreach (PSObject item in output)
        {
            WriteObject(item);
        }
    }

    private static List<object> FilterByNames(IEnumerable source, WildcardPattern functionPattern, WildcardPattern modulePattern)
    {
        List<object> filtered = new List<object>();
        foreach (object? entry in source)
        {
            if (entry is null)
            {
                continue;
            }
            string functionName = LanguagePrimitives.ConvertTo<string>(DotProperty(entry, "FunctionName")) ?? string.Empty;
            string moduleName = LanguagePrimitives.ConvertTo<string>(DotProperty(entry, "ModuleName")) ?? string.Empty;
            if (functionPattern.IsMatch(functionName) && modulePattern.IsMatch(moduleName))
            {
                filtered.Add(entry);
            }
        }
        return filtered;
    }

    // PS property access via the adapted/ETS member (PSObject-safe).
    private static object? DotProperty(object? item, string name)
    {
        if (item is null)
        {
            return null;
        }
        PSPropertyInfo? property = PSObject.AsPSObject(item).Properties[name];
        if (property is null)
        {
            return null;
        }
        try
        {
            return property.Value;
        }
        catch
        {
            return null;
        }
    }

    // PS -eq semantics (case-insensitive, conversion-based).
    private static bool PsEquals(object? left, object? right)
    {
        object? leftBase = left is PSObject leftWrapped ? leftWrapped.BaseObject : left;
        object? rightBase = right is PSObject rightWrapped ? rightWrapped.BaseObject : right;
        if (leftBase is null && rightBase is null)
        {
            return true;
        }
        return LanguagePrimitives.Equals(leftBase, rightBase, ignoreCase: true);
    }

    // PS -gt/-lt: a null RHS converts to the LHS type's default (DateTime.MinValue for
    // timestamps), so -gt $null is true and -lt $null is false for any real timestamp.
    private static bool PsGreaterThan(object? left, object? right)
    {
        try
        {
            return LanguagePrimitives.Compare(Unwrap(left), Unwrap(right), ignoreCase: true) > 0;
        }
        catch
        {
            return false;
        }
    }

    private static bool PsLessThan(object? left, object? right)
    {
        try
        {
            return LanguagePrimitives.Compare(Unwrap(left), Unwrap(right), ignoreCase: true) < 0;
        }
        catch
        {
            return false;
        }
    }

    private static object? Unwrap(object? value)
    {
        return value is PSObject wrapped ? wrapped.BaseObject : value;
    }

    // PS: Where-Object TargetObject -eq $Target - an enumerable (non-string) LHS filters
    // its elements by scalar -eq and the FILTERED RESULT's truthiness decides: none ->
    // false, one -> the element's own truthiness, many -> true.
    private static bool PsEqTruthy(object? left, object? right)
    {
        object? leftBase = Unwrap(left);
        if (leftBase is not string && LanguagePrimitives.GetEnumerable(leftBase) is IEnumerable items)
        {
            List<object?> matched = new List<object?>();
            foreach (object? item in items)
            {
                if (PsEquals(item, right))
                {
                    matched.Add(item);
                }
            }
            if (matched.Count == 0)
            {
                return false;
            }
            if (matched.Count == 1)
            {
                return LanguagePrimitives.IsTrue(matched[0]);
            }
            return true;
        }
        return PsEquals(left, right);
    }

    // PS: { $_.Tags | Where-Object { $_ -in $Tag } } - the inner filter EMITS the matching
    // tag values and the outer Where-Object applies PS truthiness to that pipeline result:
    // none -> false, one -> the tag's own truthiness (an empty string is falsy), many ->
    // true.
    private bool MatchedTagsTruthy(object? tags)
    {
        if (tags is null)
        {
            return false;
        }
        List<object?> matched = new List<object?>();
        if (LanguagePrimitives.GetEnumerable(Unwrap(tags)) is IEnumerable items)
        {
            foreach (object? item in items)
            {
                if (TagInSet(item))
                {
                    matched.Add(item);
                }
            }
        }
        else if (TagInSet(tags))
        {
            matched.Add(tags);
        }
        if (matched.Count == 0)
        {
            return false;
        }
        if (matched.Count == 1)
        {
            return LanguagePrimitives.IsTrue(matched[0]);
        }
        return true;
    }

    // PS: $_ -in $Tag - case-insensitive membership
    private bool TagInSet(object? candidate)
    {
        if (Tag is null)
        {
            return false;
        }
        foreach (string tag in Tag)
        {
            if (LanguagePrimitives.Equals(Unwrap(candidate), tag, ignoreCase: true))
            {
                return true;
            }
        }
        return false;
    }

    // PS: Where-Object Level -In $Level - enum membership
    private bool LevelMatches(object? level)
    {
        if (Level is null)
        {
            return false;
        }
        foreach (MessageLevel candidate in Level)
        {
            if (PsEquals(level, candidate))
            {
                return true;
            }
        }
        return false;
    }
}
